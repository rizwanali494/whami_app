import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/constants/connectivity_status.dart';
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
import 'region_repository.dart';
import 'landmark_repository.dart';
import 'map_repository.dart';

class WhamiRepository extends ChangeNotifier {
  final SensorManager _sensors;
  final PositionMatcher _matcher;
  final TrustFusionEngine _fusionEngine;
  final TrustEventLog _eventLog;

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

  /// Visual landmark used as a no-GPS position anchor ("Use as anchor").
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
  }) : _sensors = sensors,
       _matcher = matcher,
       _fusionEngine = fusionEngine,
       _eventLog = eventLog {
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
      _sensors.imuService.resetDeadReckoning();
      _sensors.gpsService.startListening();
      _sensors.imuService.startListening();
      _sensors.barometerService.startListening();
      _sensors.startAllWithMagAlreadyRunning();

      _sensorSub = _sensors.snapshotStream.listen((snapshot) {
        _processSnapshot(snapshot);
      });

      _eventLog.addEvent(
        title: 'Tracking Started',
        description: 'All sensor streams opened. Fusing real-time.',
        severity: 'info',
        iconName: 'play_arrow',
      );
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
    }
    notifyListeners();
  }

  /// Process live sensor snapshot and feed results into fusion algorithm
  Future<void> _processSnapshot(SensorSnapshot snapshot) async {
    final gpsReading = snapshot.gps;
    final magReading = snapshot.magnetometer;

    LandmarkMatch? lMatch;
    MagneticMatch? mMatch;
    SeamapMatch? sMatch;

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

      // Perform expected WMM magnetic baseline comparisons if region has base grid.
      // When no offline magnetic GeoJSON is loaded, fall back to the live
      // magnetometer baseline so magnetic remains a real witness in fusion.
      if (magReading != null) {
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
    );

    _opinions = fusion.opinions;
    _trustScore = fusion.confidence;

    if (fusion.alertSeverity != _alertSeverity &&
        fusion.alertSeverity != 'none') {
      _eventLog.addEvent(
        title: 'Fusion Status Change',
        description: fusion.alertMessage,
        severity: fusion.alertSeverity,
        iconName: 'warning',
      );
    }

    _alertMessage = fusion.alertMessage;
    _alertSeverity = fusion.alertSeverity;

    // Record trail
    _trail.add({'latitude': fusion.latitude, 'longitude': fusion.longitude});

    notifyListeners();
  }

  void centerMapOn(double lat, double lng) {
    mapCenterLat = lat;
    mapCenterLng = lng;
    mapRepository.updateCenter(lat, lng);
    notifyListeners();
  }

  /// Create and commit a matched visual landmark as an anchor for no-GPS fusion.
  void setLandmarkAnchor(Landmark landmark, int matchPercent) {
    _landmarkAnchor = landmark;
    // Seed the trail so IMU dead-reckoning and trusted position have a base.
    _trail.add({
      'latitude': landmark.latitude,
      'longitude': landmark.longitude,
    });
    centerMapOn(landmark.latitude, landmark.longitude);
    _eventLog.addEvent(
      title: 'Visual Anchor Set',
      description:
          '${landmark.name} matched at $matchPercent% — used as position anchor.',
      severity: 'info',
      iconName: 'anchor',
    );
    notifyListeners();
  }

  void clearLandmarkAnchor() {
    if (_landmarkAnchor == null) return;
    _landmarkAnchor = null;
    notifyListeners();
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
