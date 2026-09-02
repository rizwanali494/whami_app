import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/constants/connectivity_status.dart';
import '../../core/trust/trust_summary.dart';
import '../../features/whami_air/air_preferences.dart';
import '../../features/whami_air/air_trust.dart';
import '../models/position_opinion.dart';
import '../models/sensor_status.dart';
import '../models/region_pack.dart';
import '../models/trust_event.dart';
import '../models/landmark.dart';
import '../services/sensor_manager.dart';
import '../services/magnetometer_service.dart';
import '../services/position_matcher.dart';
import '../services/trust_fusion_engine.dart';
import '../services/trust_event_log.dart';
import '../services/raster_tile_cache_service.dart';
import '../services/maplibre_connectivity_service.dart';
import '../services/glyph_server.dart';
import '../services/wmm/wmm_service.dart';
import '../services/wmm/wmm_field.dart';
import '../services/air_research_recorder.dart';
import '../services/magnetic_trust_model.dart';
import '../services/trust_timeline_recorder.dart';
import '../models/trust_timeline_sample.dart';
import 'region_repository.dart';
import 'landmark_repository.dart';
import 'map_repository.dart';

class WhamiRepository extends ChangeNotifier {
  final SensorManager _sensors;
  final PositionMatcher _matcher;
  final TrustFusionEngine _fusionEngine;
  final TrustEventLog _eventLog;
  final WmmService wmmService;
  final AirResearchRecorder airRecorder;
  final MagCalibration magCalibration;
  final KpIndexService kpService;
  MagneticAnomalyLayer anomalyLayer;

  // Delegated Sub-Repositories
  final RegionRepository regionRepository;
  final LandmarkRepository landmarkRepository;
  final MapRepository mapRepository;
  final RasterTileCacheService rasterTileCacheService;
  final GlyphServer glyphServer;

  // Live navigation state
  List<PositionOpinion> _opinions = [];
  int _trustScore = 75;
  String _alertMessage = 'Positions aligned. System nominal.';
  String _alertSeverity = 'none';
  bool _isTracking = false;
  final List<Map<String, double>> _trail = [];
  List<Landmark> _activePackLandmarks = [];
  AirTrustSnapshot? _airTrust;
  WmmResidual? _lastWmmResidual;
  FusedPosition? _lastFusion;
  final TrustTimelineRecorder trustTimeline = TrustTimelineRecorder();
  bool _spoofAlarmVisible = false;
  bool _spoofAlarmDismissed = false;

  /// Visual landmark used as a real-world lock / no-GPS anchor.
  Landmark? _landmarkAnchor;

  // Cache of the last GPS fix a landmark query was run for, so snapshots
  // triggered purely by IMU/magnetometer/barometer ticks (which can fire at
  // several Hz) don't each re-issue an expensive SQLite lookup.
  DateTime? _lastLandmarkQueryGpsTimestamp;
  LandmarkMatch? _lastLandmarkMatch;

  // Active pack coordinate coordinates cache
  static const Map<String, List<double>> _packCoordinates = {
    'sf_bay': [37.7140, -122.3078],
    'tahoe': [39.0885, -120.0504],
    'mountain_view': [37.1413, -121.9974],
    'rotterdam': [51.9043, 4.4298],
    'coastal_demo': [32.7, -117.4],
  };

  // Connectivity state
  ConnectivityMode _connectivityMode = ConnectivityMode.offline;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Stream Subscriptions
  StreamSubscription? _sensorSub;
  StreamSubscription? _magFeedSub;
  MagnetometerReading? _lastMagReading;

  // Map center overrides (optional)
  double? mapCenterLat;
  double? mapCenterLng;

  // Getters
  SensorManager get sensors => _sensors;
  TrustEventLog get eventLog => _eventLog;
  AirTrustSnapshot? get airTrust => _airTrust;
  WmmResidual? get lastWmmResidual => _lastWmmResidual;
  FusedPosition? get lastFusion => _lastFusion;
  Landmark? get landmarkAnchor => _landmarkAnchor;
  bool get hasRealWorldLock => _landmarkAnchor != null;
  bool get gnssSuspicious => _lastFusion?.gnssSuspicious ?? false;
  bool get showSpoofAlarm =>
      _spoofAlarmVisible &&
      !_spoofAlarmDismissed &&
      (_lastFusion?.gnssSuspicious == true);

  List<PositionOpinion> get positionOpinions => _opinions;
  int get trustScore => _trustScore;
  String get alertMessage => _alertMessage;
  String get alertSeverity => _alertSeverity;
  bool get isTracking => _isTracking;
  List<Map<String, double>> get trail => _trail;

  // Proxy region properties
  String get activePackId => regionRepository.activePackId;
  RegionPack? get activeRegionPack =>
      regionRepository.regionEngine.activeRegionPack;
  List<RegionPack> get packs => regionRepository.packs;
  ConnectivityMode get connectivityMode => _connectivityMode;

  /// Base URL of the local MBTiles tile server (e.g. 'http://127.0.0.1:52341')
  /// Empty string when no pack is active or server has not started yet.
  String get tileServerBaseUrl =>
      regionRepository.regionEngine.tileServer.baseUrl;

  ConnectivityState get connectivityState {
    final activePack = activeRegionPack;
    final packName = activePack?.name ?? 'No Pack';
    final hasPack = activePack != null && activePack.status == 'downloaded';
    final status = hasPack ? 'Active' : 'Not Loaded';

    return ConnectivityState(
      mode: _connectivityMode,
      activePackName: packName,
      packCoverageStatus: status,
    );
  }

  WhamiRepository({
    required SensorManager sensors,
    required PositionMatcher matcher,
    required TrustFusionEngine fusionEngine,
    required TrustEventLog eventLog,
    required this.regionRepository,
    required this.landmarkRepository,
    required this.mapRepository,
    required this.rasterTileCacheService,
    required this.glyphServer,
    required this.wmmService,
    required this.airRecorder,
    MagCalibration? magCalibration,
    KpIndexService? kpService,
    MagneticAnomalyLayer? anomalyLayer,
  }) : _sensors = sensors,
       _matcher = matcher,
       _fusionEngine = fusionEngine,
       _eventLog = eventLog,
       magCalibration = magCalibration ?? MagCalibration(),
       kpService = kpService ?? KpIndexService(),
       anomalyLayer = anomalyLayer ?? MagneticAnomalyLayer.empty() {
    _initDefaultPack();
    _initConnectivity();
    regionRepository.addListener(notifyListeners);
    landmarkRepository.addListener(notifyListeners);
    mapRepository.addListener(notifyListeners);
  }

  /// Center the map near the user on boot. No pack is auto-activated —
  /// regions are only ever activated by explicit user choice on the Region
  /// Packs screen, so the map starts in raster-basemap mode every launch.
  Future<void> _initDefaultPack() async {
    // Do not block launch on GPS permission — center on a neutral default,
    // then refine asynchronously once a fix is available.
    centerMapOn(
      _packCoordinates['sf_bay']![0],
      _packCoordinates['sf_bay']![1],
    );
    _eventLog.seedInitialEvents();
    notifyListeners();

    unawaited(() async {
      try {
        await _sensors.gpsService.initialize();
        final loc = await _sensors.gpsService.getCurrentPosition();
        if (loc != null) {
          centerMapOn(loc.latitude, loc.longitude);
        }
      } catch (e) {
        debugPrint('[WhamiRepository] Deferred GPS center failed: $e');
      }
    }());
  }

  void _initConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final activePack = regionRepository.getRegionPackById(activePackId);
      final packName = activePack?.name ?? 'No Pack';
      final hasPack = activePack != null && activePack.status == 'downloaded';
      final status = hasPack ? 'Active' : 'Not Loaded';

      final state = ConnectivityState.fromResults(
        results,
        activePackName: packName,
        packCoverageStatus: status,
      );
      _connectivityMode = state.mode;

      // MapLibre Native runs its own connectivity receiver alongside this
      // one, and re-queries the real OS state whenever it changes — which
      // clobbers the forced-connected override the map relies on to keep
      // fetching from its local loopback tile server(s) while genuinely
      // offline. Reassert it right here, every time real connectivity
      // changes, so it's never left clobbered.
      MapLibreConnectivityService.forceConnected();

      notifyListeners();
    });
  }

  set connectivityMode(ConnectivityMode mode) {
    if (_connectivityMode != mode) {
      _connectivityMode = mode;
      notifyListeners();
    }
  }

  // Proxy actions delegated to sub-repositories
  void startDownload(String packId) => regionRepository.startDownload(packId);
  Future<void> cancelDownload(String packId) =>
      regionRepository.cancelDownload(packId);
  Future<void> deleteRegionPack(String packId) =>
      regionRepository.deleteRegionPack(packId);

  Future<void> activateRegionPack(String packId) async {
    clearLandmarkAnchor();
    await regionRepository.activateRegionPack(packId);

    if (_isTracking) {
      toggleTracking();
    }

    final activePack = regionRepository.getRegionPackById(packId);
    if (activePack?.metadata != null) {
      final bounds = activePack!.metadata!.bounds;
      if (bounds.length == 4 && bounds[0] != 0 && bounds[1] != 0) {
        final lat = (bounds[0] + bounds[2]) / 2.0;
        final lng = (bounds[1] + bounds[3]) / 2.0;
        centerMapOn(lat, lng);
      }
    } else if (_packCoordinates.containsKey(packId)) {
      centerMapOn(_packCoordinates[packId]![0], _packCoordinates[packId]![1]);
    }
    // Load active pack landmarks cache for legacy synchronous API
    try {
      _activePackLandmarks = await landmarkRepository.getVisibleLandmarks(
        -90,
        -180,
        90,
        180,
        limit: 1000,
      );
      mapRepository.updateVisibleLandmarks(_activePackLandmarks);
    } catch (_) {
      _activePackLandmarks = [];
    }

    _eventLog.addEvent(
      title: 'Region Activated',
      description:
          'Pack "${regionRepository.getRegionPackById(packId)?.name ?? packId}" is now the active region.',
      severity: 'info',
      iconName: 'map',
    );
    notifyListeners();
  }

  Future<void> deactivateRegionPack() async {
    clearLandmarkAnchor();
    await regionRepository.deactivateRegionPack();
    _activePackLandmarks = [];
    mapRepository.updateVisibleLandmarks([]);
    _eventLog.addEvent(
      title: 'Region Deactivated',
      description: 'Pack unloaded from local view.',
      severity: 'info',
      iconName: 'map',
    );
    notifyListeners();
  }

  List<RegionPack> getRegionPacks() => packs;
  RegionPack? getRegionPackById(String id) =>
      regionRepository.getRegionPackById(id);

  /// Start background magnetometer feed from physical hardware
  void startMagnetometerFeed() {
    final magService = _sensors.magnetometerService;
    if (!magService.isAvailable) return;

    _magFeedSub?.cancel();
    _magFeedSub = magService.stream.listen((reading) {
      _lastMagReading = reading;
      if (!_isTracking) {
        notifyListeners();
      }
    });
  }

  /// Enable or disable tracking and sensor streams
  void toggleTracking() {
    _isTracking = !_isTracking;
    if (_isTracking) {
      _trail.clear();
      trustTimeline.clear();
      _spoofAlarmDismissed = false;
      _spoofAlarmVisible = false;
      _sensors.imuService.resetDeadReckoning();
      _sensors.gpsService.startListening();
      _sensors.imuService.startListening();
      _sensors.barometerService.startListening();
      _sensors.startAllWithMagAlreadyRunning();

      _sensorSub = _sensors.snapshotStream.listen((snapshot) {
        _processSnapshot(snapshot);
      });

      _eventLog.addEvent(
        title: TrustEvent.trackingStarted().title,
        description: TrustEvent.trackingStarted().description,
        severity: 'info',
        iconName: 'gps_fixed',
      );

      if (airPreferences.airModeEnabled && airPreferences.recordingEnabled) {
        unawaited(
          airRecorder.startFlight(
            meta: {
              'wmmModel': wmmService.modelName,
              'wmmEpoch': wmmService.epoch,
              'kp': kpService.kp,
              'anomalyLayer': anomalyLayer.hasData ? 'loaded' : 'none',
            },
          ),
        );
      }
    } else {
      _sensorSub?.cancel();
      _sensorSub = null;
      _sensors.stopAllKeepMagnetometer();

      _eventLog.addEvent(
        title: 'Tracking Stopped',
        description: 'Sensor streams closed. Magnetometer still active.',
        severity: 'info',
        iconName: 'stop',
      );

      if (airRecorder.isRecording) {
        unawaited(airRecorder.stopFlight());
      }
    }
    notifyListeners();
  }

  /// Process live sensor snapshot and feed results into fusion algorithm
  Future<void> _processSnapshot(SensorSnapshot snapshot) async {
    final gpsReading = snapshot.gps;
    var magReading = snapshot.magnetometer;

    LandmarkMatch? lMatch;
    MagneticMatch? mMatch;
    SeamapMatch? sMatch;
    double? wmmResidualUt;
    int? wmmAgreementScore;
    String? wmmStatus;
    String? wmmDescription;
    WmmResidual? wmmRes;

    if (magReading != null && magCalibration.calibrated) {
      final c = magCalibration.apply(magReading.x, magReading.y, magReading.z);
      final strength = magCalibration.fieldStrength(
        magReading.x,
        magReading.y,
        magReading.z,
      );
      magReading = MagnetometerReading(
        x: c.$1,
        y: c.$2,
        z: c.$3,
        heading: magReading.heading,
        fieldStrength: strength,
        timestamp: magReading.timestamp,
      );
    }

    if (gpsReading != null) {
      // Snapshots fire on every sensor tick (IMU alone ticks at 5Hz), but the
      // cached GPS reading only actually changes when a new fix arrives.
      // Skip the SQLite lookup for repeat snapshots referencing the same fix.
      if (_lastLandmarkQueryGpsTimestamp != gpsReading.timestamp) {
        // Query SQLite database for landmarks within 5km radius
        final nearbyLandmarks = await landmarkRepository.getNearbyLandmarks(
          gpsReading.latitude,
          gpsReading.longitude,
          5000.0,
        );

        lMatch = _matcher.matchLandmarksList(
          latitude: gpsReading.latitude,
          longitude: gpsReading.longitude,
          landmarks: nearbyLandmarks,
        );

        _lastLandmarkQueryGpsTimestamp = gpsReading.timestamp;
        _lastLandmarkMatch = lMatch;
      } else {
        lMatch = _lastLandmarkMatch;
      }

      // Prefer official WMM when available; else live baseline / pack match.
      if (magReading != null && wmmService.isReady) {
        final altKm = (gpsReading.altitude.isFinite
                ? gpsReading.altitude
                : 0.0) /
            1000.0;
        wmmRes = wmmService.residual(
          latitudeDeg: gpsReading.latitude,
          longitudeDeg: gpsReading.longitude,
          measuredFMicroTesla: magReading.fieldStrength,
          altitudeKm: altKm.clamp(-1.0, 100.0),
          kpIndex: airPreferences.airModeEnabled
              ? airPreferences.kpIndex
              : kpService.kp,
        );
        // Optional anomaly layer adjusts expected F before residual display.
        if (anomalyLayer.hasData) {
          final dF =
              anomalyLayer.deltaFnT(gpsReading.latitude, gpsReading.longitude) /
                  1000.0; // nT → µT
          final adjustedMeasured = magReading.fieldStrength - dF;
          wmmRes = wmmService.residual(
            latitudeDeg: gpsReading.latitude,
            longitudeDeg: gpsReading.longitude,
            measuredFMicroTesla: adjustedMeasured,
            altitudeKm: altKm.clamp(-1.0, 100.0),
            kpIndex: airPreferences.kpIndex,
          );
        }
        _lastWmmResidual = wmmRes;
        wmmResidualUt = wmmRes.residualMicroTesla;
        wmmAgreementScore = wmmRes.agreementScore;
        wmmStatus = wmmRes.status;
        wmmDescription = wmmRes.description;
        mMatch = MagneticMatch(
          expectedStrength: wmmRes.model.fMicroTesla,
          stability: (wmmRes.agreementScore / 100).clamp(0.2, 1.0),
          deviation: wmmRes.residualMicroTesla,
        );
      } else if (magReading != null) {
        final magService = _sensors.magnetometerService;
        mMatch = MagneticMatch(
          expectedStrength: magService.baselineStrength > 0
              ? magService.baselineStrength
              : 50.0,
          stability: (magService.getConfidence() / 100).clamp(0.2, 1.0),
          deviation: magService.baselineStrength > 0
              ? (magReading.fieldStrength - magService.baselineStrength).abs()
              : 0.0,
        );
      } else {
        mMatch = null;
      }
      // Seamap matching requires offline channel geometry; keep null until pack
      // exposes seamap GeoJSON through the region engine.
      sMatch = null;
    }

    double? lastLat = _trail.isNotEmpty ? _trail.last['latitude'] : null;
    double? lastLng = _trail.isNotEmpty ? _trail.last['longitude'] : null;

    final fusion = _fusionEngine.compute(
      gps: gpsReading,
      magnetometer: magReading,
      imu: snapshot.imu,
      barometer: snapshot.barometer,
      sky: snapshot.sky,
      landmarkMatch: lMatch,
      magneticMatch: mMatch,
      seamapMatch: sMatch,
      hasOfflineData: activePackId.isNotEmpty,
      lastTrustedLat: lastLat,
      lastTrustedLng: lastLng,
      landmarkAnchorLat: _landmarkAnchor?.latitude,
      landmarkAnchorLng: _landmarkAnchor?.longitude,
      landmarkAnchorName: _landmarkAnchor?.name,
      wmmResidualUt: wmmResidualUt,
      wmmAgreementScore: wmmAgreementScore,
      wmmStatus: wmmStatus,
      wmmDescription: wmmDescription,
    );

    _lastFusion = fusion;
    _opinions = fusion.opinions;
    _trustScore = fusion.confidence;

    final summary = TrustSummary.fromOpinions(
      trustScore: fusion.confidence,
      opinions: fusion.opinions,
      isTracking: true,
    );
    final activeCount =
        fusion.opinions.where((o) => o.status == 'active').length;
    final band = airTrustBandFrom(
      trustScore: fusion.confidence,
      level: summary.level,
      isTracking: true,
      activeWitnesses: activeCount,
    );
    _airTrust = AirTrustSnapshot(
      band: band,
      positionTrust: fusion.confidence,
      confidenceRadiusM: fusion.uncertaintyRadius,
      gnssSuspicious: fusion.gnssSuspicious,
      gnssUnavailable: gpsReading == null,
      magneticAgreement: fusion.magneticAgreement,
      baroConsistency: fusion.baroConsistency,
      celestialAgreement: fusion.celestialAgreement,
      wmmResidualUt: fusion.wmmResidualUt,
      baroGpsAltDeltaM: fusion.baroGpsAltDeltaM,
      sourceHierarchy: fusion.sourceHierarchy,
      advisoryMessage: fusion.alertMessage,
    );

    if (fusion.alertSeverity != _alertSeverity &&
        fusion.alertSeverity != 'none') {
      if (fusion.gnssSuspicious) {
        _eventLog.add(
          TrustEvent.gpsJump(
            distance: fusion.uncertaintyRadius,
          ),
        );
      } else {
        _eventLog.addEvent(
          title: 'Fusion Status Change',
          description: fusion.alertMessage,
          severity: fusion.alertSeverity,
          iconName: 'warning',
        );
      }
    }

    if (fusion.gnssSuspicious) {
      _spoofAlarmVisible = true;
      if (_alertSeverity != 'critical' && _alertSeverity != 'warning') {
        // Rising edge handled above; keep banner sticky until dismiss/clear.
      }
    } else if (!fusion.gnssSuspicious && _spoofAlarmVisible) {
      // Auto-clear sticky alarm once witnesses agree again.
      _spoofAlarmVisible = false;
      _spoofAlarmDismissed = false;
    }

    _alertMessage = fusion.alertMessage;
    _alertSeverity = fusion.alertSeverity;

    // Record trail + trust timeline sample (throttled to ~1 Hz via trail length)
    _trail.add({'latitude': fusion.latitude, 'longitude': fusion.longitude});
    _recordTimelineSample(fusion, summary);

    if (airPreferences.airModeEnabled &&
        airPreferences.recordingEnabled &&
        airRecorder.isRecording &&
        _airTrust != null) {
      unawaited(
        airRecorder.appendFromSensors(
          air: _airTrust!,
          gnss: gpsReading == null
              ? null
              : {
                  'lat': gpsReading.latitude,
                  'lng': gpsReading.longitude,
                  'alt': gpsReading.altitude,
                  'acc': gpsReading.accuracy,
                  'speed': gpsReading.speed,
                },
          mag: magReading == null
              ? null
              : {
                  'x': magReading.x,
                  'y': magReading.y,
                  'z': magReading.z,
                  'f': magReading.fieldStrength,
                  'heading': magReading.heading,
                },
          imu: snapshot.imu == null
              ? null
              : {
                  'dx': snapshot.imu!.displacementX,
                  'dy': snapshot.imu!.displacementY,
                  'motion': snapshot.imu!.motionType.name,
                },
          baro: snapshot.barometer == null
              ? null
              : {
                  'hPa': snapshot.barometer!.pressure,
                  'altM': snapshot.barometer!.estimatedAltitude,
                },
          sky: snapshot.sky == null
              ? null
              : {
                  'sunAz': snapshot.sky!.sunAzimuth,
                  'sunEl': snapshot.sky!.sunElevation,
                  'conf': snapshot.sky!.confidence,
                },
          wmm: wmmRes == null
              ? null
              : {
                  'F_uT': wmmRes.model.fMicroTesla,
                  'residual_uT': wmmRes.residualMicroTesla,
                  'decl': wmmRes.model.declination,
                },
          kpIndex: airPreferences.kpIndex,
        ),
      );
    }

    notifyListeners();
  }

  void centerMapOn(double lat, double lng) {
    mapCenterLat = lat;
    mapCenterLng = lng;
    mapRepository.updateCenter(lat, lng);
    notifyListeners();
  }

  /// Create and commit a matched visual landmark as a real-world lock.
  void setLandmarkAnchor(Landmark landmark, int matchPercent) {
    _landmarkAnchor = landmark;
    // Seed the trail so IMU dead-reckoning and trusted position have a base.
    _trail.add({
      'latitude': landmark.latitude,
      'longitude': landmark.longitude,
    });
    centerMapOn(landmark.latitude, landmark.longitude);
    _eventLog.add(
      TrustEvent.landmarkMatched(
        landmarkName: landmark.name,
        confidence: matchPercent,
      ),
    );
    notifyListeners();
  }

  void clearLandmarkAnchor() {
    if (_landmarkAnchor == null) return;
    _landmarkAnchor = null;
    _eventLog.addEvent(
      title: 'Real-World Lock Cleared',
      description: 'Visual landmark lock removed.',
      severity: 'info',
      iconName: 'lock_open',
    );
    notifyListeners();
  }

  void dismissSpoofAlarm() {
    _spoofAlarmDismissed = true;
    notifyListeners();
  }

  DateTime? _lastTimelineSampleAt;

  void _recordTimelineSample(FusedPosition fusion, TrustSummary summary) {
    final now = DateTime.now();
    // ~1 Hz to keep memory reasonable while tracking.
    if (_lastTimelineSampleAt != null &&
        now.difference(_lastTimelineSampleAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastTimelineSampleAt = now;

    final scores = <String, int>{};
    final broken = <String>[];
    for (final op in fusion.opinions) {
      if (op.status == 'unavailable') continue;
      scores[op.shortCode] = op.confidence;
      if (op.status == 'unstable' || op.confidence < 55) {
        broken.add(op.name);
      }
    }

    trustTimeline.add(
      TrustTimelineSample(
        timestamp: now,
        trustScore: fusion.confidence,
        level: summary.level.name,
        latitude: fusion.latitude,
        longitude: fusion.longitude,
        uncertaintyM: fusion.uncertaintyRadius,
        gnssSuspicious: fusion.gnssSuspicious,
        alertMessage: fusion.alertSeverity == 'none' ? null : fusion.alertMessage,
        witnessScores: scores,
        brokenWitnesses: broken,
      ),
    );
  }

  /// Record AR visual confirmation match scores
  void recordArScanResult({
    required String poseQuality,
    required int visualMatch,
  }) {
    _eventLog.addEvent(
      title: 'AR Visual Confirmation',
      description:
          'AR Scan completed — pose quality: $poseQuality, visual match: $visualMatch%.',
      severity: visualMatch >= 80 ? 'info' : 'warning',
      iconName: 'view_in_ar',
    );
    notifyListeners();
  }

  PositionOpinion getTrustedPosition() {
    try {
      return getPositionOpinions().firstWhere((o) => o.sourceType == 'whami');
    } catch (_) {
      final lastLat = _trail.isNotEmpty ? _trail.last['latitude']! : 37.8087;
      final lastLng = _trail.isNotEmpty ? _trail.last['longitude']! : -122.4098;
      return PositionOpinion.whami(
        latitude: lastLat,
        longitude: lastLng,
        confidence: _trustScore,
        uncertaintyRadius: 30,
        description: _alertMessage,
      );
    }
  }

  List<PositionOpinion> getPositionOpinions() {
    if (_opinions.isEmpty) {
      final magService = _sensors.magnetometerService;
      final magReading = _lastMagReading;
      final magConfidence = magService.getConfidence();
      final hasMagSignal = magReading != null && magService.isAvailable;

      return [
        PositionOpinion.unavailable(
          id: 'gps',
          name: 'GPS / GNSS',
          shortCode: 'G',
          sourceType: 'gps',
          colorName: 'blue',
        ),
        PositionOpinion.unavailable(
          id: 'landmark',
          name: 'Landmark / Seamap',
          shortCode: 'L',
          sourceType: 'landmark',
          colorName: 'black',
        ),
        if (hasMagSignal)
          PositionOpinion.fromMagnetic(
            latitude: 0,
            longitude: 0,
            confidence: magConfidence,
            uncertaintyRadius: magService.detectInterference() ? 500.0 : 150.0,
            status: 'verify',
            description:
                'Compass verify-only: ${magReading.heading.toStringAsFixed(0)}°',
          )
        else
          PositionOpinion.unavailable(
            id: 'magnetic',
            name: 'Magnetic Field',
            shortCode: 'M',
            sourceType: 'magnetic',
            colorName: 'red',
          ),
      ];
    }
    return _opinions;
  }

  int getTrustScore() => _trustScore;
  String getAlertMessage() => _alertMessage;
  List<SensorStatus> getSensorStatuses() {
    final list = List<SensorStatus>.from(_sensors.getSensorStatuses());
    list.add(
      SensorStatus(
        id: 'fusion',
        name: 'Trust Fusion Engine',
        status: _isTracking ? 'active' : 'available',
        confidence: _trustScore,
        latestValue: _isTracking
            ? 'Consensus confidence: $_trustScore%'
            : 'Ready',
        healthMessage: _alertMessage,
        iconName: 'security',
        lastUpdated: DateTime.now(),
      ),
    );
    return list;
  }

  List<TrustEvent> getTrustEvents() => _eventLog.getEvents();

  Map<String, dynamic> getTrustBreakdown() {
    final ops = getPositionOpinions();
    int landmark = 0;
    int gps = 0;
    int magnetic = 0;
    int imu = 0;
    int sky = 0;

    for (final op in ops) {
      if (op.status == 'active') {
        if (op.sourceType == 'landmark') landmark = op.confidence;
        if (op.sourceType == 'gps') gps = op.confidence;
        if (op.sourceType == 'magnetic') magnetic = op.confidence;
        if (op.sourceType == 'imu') imu = op.confidence;
        if (op.sourceType == 'sextant') sky = op.confidence;
      }
    }

    return {
      'finalScore': _trustScore,
      'landmarkMatch': landmark,
      'gpsConfidence': gps,
      'magneticFit': magnetic,
      'imuPath': imu,
      'skyStability': sky,
    };
  }

  /// Legacy helper method to get all landmarks for the active region (compatibility proxy)
  List<Landmark> getLandmarks() {
    return _activePackLandmarks;
  }

  @override
  void dispose() {
    regionRepository.removeListener(notifyListeners);
    landmarkRepository.removeListener(notifyListeners);
    mapRepository.removeListener(notifyListeners);
    _connectivitySub?.cancel();
    _sensorSub?.cancel();
    _magFeedSub?.cancel();
    super.dispose();
  }
}
