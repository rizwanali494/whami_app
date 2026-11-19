import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/map_basemap_style.dart';
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
import '../services/gps_service.dart';
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
import '../services/evidence_pack_exporter.dart';
import '../services/geometry_snap_service.dart';
import '../services/witness_crossfire.dart';
import '../services/flight_plan_store.dart';
import '../services/route_progress.dart';
import '../services/truth_mode_service.dart';
import '../services/witness_mesh_service.dart';
import '../services/spoof_heatmap_service.dart';
import '../services/trust_copilot.dart';
import '../models/flight_plan.dart';
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
  final EvidencePackExporter evidenceExporter = EvidencePackExporter();
  final GeometrySnapService geometrySnap = GeometrySnapService();
  final FlightPlanStore flightPlanStore = FlightPlanStore();
  final TruthModeService truthMode = TruthModeService();
  final WitnessMeshService witnessMesh = WitnessMeshService();
  final SpoofHeatmapService spoofHeatmap = SpoofHeatmapService();
  final TrustCopilot trustCopilot = TrustCopilot();
  FlightPlan? _activeFlightPlan;
  bool _flightPlanEditMode = false;
  MapBasemapStyle _mapBasemapStyle = MapBasemapStyle.street;
  static const _prefsBasemapKey = 'whami_map_basemap_style_v1';
  String? _activatingPackId;
  bool _deactivatingPack = false;

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
  /// When false while tracking, GPS stream is paused (mag/IMU/baro continue).
  bool _gpsEnabled = true;
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
    // Tocumwal Aerodrome (YTOC) — Victoria / NSW Riverina demo.
    'aus_victoria_nsw': [-35.8117, 145.6083],
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

  /// Raw GPS claim when spoofing — map ghost pin.
  double? get gpsClaimLat => _lastFusion?.gpsClaimLatitude;
  double? get gpsClaimLng => _lastFusion?.gpsClaimLongitude;

  /// Trusted fuse / lock position (solid pin). Null when no real fix.
  double? get trustedLat =>
      (_lastFusion?.hasValidFix ?? false) ? _lastFusion!.latitude : null;
  double? get trustedLng =>
      (_lastFusion?.hasValidFix ?? false) ? _lastFusion!.longitude : null;

  /// Distance between GPS claim and trusted reality (meters).
  double? get lieDistanceM => _lastFusion?.lieDistanceM;

  /// Show Ghost Pin when GPS claim and trusted coords diverge meaningfully.
  /// Hidden for continental distances (stale lock / region change).
  bool get showGhostPin {
    if (!gnssSuspicious) return false;
    final gLat = gpsClaimLat;
    final gLng = gpsClaimLng;
    final tLat = trustedLat;
    final tLng = trustedLng;
    final dist = lieDistanceM;
    if (gLat == null || gLng == null || tLat == null || tLng == null) {
      return false;
    }
    if (dist == null || dist <= 50) return false;
    if (dist > TrustFusionEngine.maxPlausibleSpoofJumpM) return false;
    return true;
  }

  /// Witness Crossfire jury — visible when trust is shaky or GPS is lying.
  WitnessCrossfire get crossfire {
    final fusion = _lastFusion;
    if (fusion == null || !_isTracking) return WitnessCrossfire.empty;
    return WitnessCrossfire.fromOpinions(
      opinions: fusion.opinions,
      trustedLat: fusion.latitude,
      trustedLng: fusion.longitude,
      trustScore: fusion.confidence,
      gnssSuspicious: fusion.gnssSuspicious,
      isTracking: _isTracking,
    );
  }

  List<PositionOpinion> get positionOpinions => _opinions;
  int get trustScore => _trustScore;
  String get alertMessage => _alertMessage;
  String get alertSeverity => _alertSeverity;
  bool get isTracking => _isTracking;
  bool get gpsEnabled => _gpsEnabled;
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
    unawaited(_loadFlightPlan());
    unawaited(_loadBasemapStyle());
    regionRepository.addListener(notifyListeners);
    landmarkRepository.addListener(notifyListeners);
    mapRepository.addListener(notifyListeners);
  }

  FlightPlan? get activeFlightPlan => _activeFlightPlan;
  bool get flightPlanEditMode => _flightPlanEditMode;
  MapBasemapStyle get mapBasemapStyle => _mapBasemapStyle;

  /// Legacy: true for satellite or hybrid imagery styles.
  bool get satelliteBasemap => _mapBasemapStyle.isImagery;
  String? get activatingPackId => _activatingPackId;
  bool get isActivatingPack => _activatingPackId != null;
  bool get isDeactivatingPack => _deactivatingPack;

  void setSatelliteBasemap(bool enabled) {
    setMapBasemapStyle(
      enabled ? MapBasemapStyle.satellite : MapBasemapStyle.street,
    );
  }

  void setMapBasemapStyle(MapBasemapStyle style) {
    if (_mapBasemapStyle == style) return;
    _mapBasemapStyle = style;
    notifyListeners();
    unawaited(_persistBasemapStyle(style));
  }

  Future<void> _loadBasemapStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefsBasemapKey);
      if (id == null) return;
      final next = MapBasemapStyleX.fromId(id);
      if (next != _mapBasemapStyle) {
        _mapBasemapStyle = next;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[WhamiRepository] basemap style load failed: $e');
    }
  }

  Future<void> _persistBasemapStyle(MapBasemapStyle style) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsBasemapKey, style.id);
    } catch (e) {
      debugPrint('[WhamiRepository] basemap style save failed: $e');
    }
  }

  /// WHAMI trusted fix vs active task line (null if no route / no fix).
  RouteProgress? get routeProgress {
    final plan = _activeFlightPlan;
    // Need a real-length polyline — coincident pins are not a route yet.
    if (plan == null || !plan.hasRoute || plan.totalLengthM < 5) return null;
    final lat = trustedLat ??
        (_trail.isNotEmpty ? _trail.last['latitude'] : null);
    final lng = trustedLng ??
        (_trail.isNotEmpty ? _trail.last['longitude'] : null);
    if (lat == null || lng == null) return null;
    return RouteProgress.fromPlan(plan: plan, lat: lat, lng: lng);
  }

  Future<void> _loadFlightPlan() async {
    final plan = await flightPlanStore.loadActive();
    if (plan == null) return;
    _activeFlightPlan = plan;
    notifyListeners();
  }

  void setFlightPlanEditMode(bool enabled) {
    if (_flightPlanEditMode == enabled) return;
    _flightPlanEditMode = enabled;
    if (enabled && _activeFlightPlan == null) {
      _activeFlightPlan = FlightPlan.empty(name: 'Travel route');
    }
    if (!enabled) _finalizeTravelRouteLabels();
    notifyListeners();
  }

  /// Origin → enroute WPs → Destination once the pilot finishes placing.
  void _finalizeTravelRouteLabels() {
    final plan = _activeFlightPlan;
    if (plan == null || plan.waypoints.length < 2) return;
    final wps = <FlightWaypoint>[];
    for (var i = 0; i < plan.waypoints.length; i++) {
      final w = plan.waypoints[i];
      final auto = RegExp(r'^(Pin|WP)\s*\d+$', caseSensitive: false)
          .hasMatch(w.name.trim());
      if (i == 0 && (auto || w.name == 'Start')) {
        wps.add(w.copyWith(name: 'Origin'));
      } else if (i == plan.waypoints.length - 1 && auto) {
        wps.add(w.copyWith(name: 'Destination'));
      } else {
        wps.add(w);
      }
    }
    _activeFlightPlan = plan.copyWith(waypoints: wps, updatedAt: DateTime.now());
  }

  Future<void> saveActiveFlightPlan({String? name}) async {
    final plan = _activeFlightPlan;
    if (plan == null) return;
    final next = plan.copyWith(
      name: name ?? plan.name,
      updatedAt: DateTime.now(),
    );
    _activeFlightPlan = next;
    await flightPlanStore.saveActive(next);
    _eventLog.addEvent(
      title: 'Flight plan saved',
      description: '${next.name} · ${next.waypoints.length} waypoints',
      severity: 'info',
      iconName: 'route',
    );
    notifyListeners();
  }

  Future<void> clearActiveFlightPlan() async {
    _activeFlightPlan = null;
    _flightPlanEditMode = false;
    await flightPlanStore.clearActive();
    notifyListeners();
  }

  /// Drop a pin on the travel route (ordered ahead of you along the plan).
  void addFlightWaypoint({
    required double latitude,
    required double longitude,
    String? name,
  }) {
    final plan = _activeFlightPlan ?? FlightPlan.empty(name: 'Travel route');
    final n = plan.waypoints.length + 1;
    final defaultName =
        n == 1 ? 'Origin' : 'WP${n.toString().padLeft(2, '0')}';
    final wp = FlightWaypoint(
      id: 'wp_${DateTime.now().millisecondsSinceEpoch}_$n',
      name: name ?? defaultName,
      latitude: latitude,
      longitude: longitude,
    );
    _activeFlightPlan = plan.copyWith(
      waypoints: [...plan.waypoints, wp],
      updatedAt: DateTime.now(),
    );
    if (!_flightPlanEditMode) _flightPlanEditMode = true;
    notifyListeners();
  }

  /// Start a new travel route in pin-placing mode (map taps drop pins).
  void beginTravelRoutePlanning() {
    _activeFlightPlan ??= FlightPlan.empty(name: 'Travel route');
    _flightPlanEditMode = true;
    notifyListeners();
  }

  void renameFlightWaypoint(String id, String name) {
    final plan = _activeFlightPlan;
    if (plan == null) return;
    _activeFlightPlan = plan.copyWith(
      waypoints: plan.waypoints
          .map((w) => w.id == id ? w.copyWith(name: name.trim()) : w)
          .toList(),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void removeFlightWaypoint(String id) {
    final plan = _activeFlightPlan;
    if (plan == null) return;
    _activeFlightPlan = plan.copyWith(
      waypoints: plan.waypoints.where((w) => w.id != id).toList(),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
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
    if (_activatingPackId != null || _deactivatingPack) return;
    _activatingPackId = packId;
    notifyListeners(); // show loading immediately

    try {
      clearLandmarkAnchor();
      await regionRepository.activateRegionPack(packId);

      if (_isTracking) {
        toggleTracking();
      }

      final activePack = regionRepository.getRegionPackById(packId);
      final metaBounds = activePack?.metadata?.bounds;
      double minLat = -90, minLng = -180, maxLat = 90, maxLng = 180;
      if (metaBounds != null && metaBounds.length == 4) {
        minLat = metaBounds[0];
        minLng = metaBounds[1];
        maxLat = metaBounds[2];
        maxLng = metaBounds[3];
        if (minLat != 0 || minLng != 0) {
          centerMapOn((minLat + maxLat) / 2.0, (minLng + maxLng) / 2.0);
        }
      } else if (_packCoordinates.containsKey(packId)) {
        centerMapOn(_packCoordinates[packId]![0], _packCoordinates[packId]![1]);
      }

      // Status bar can flip to "Loaded" before landmark cache finishes.
      notifyListeners();

      try {
        _activePackLandmarks = await landmarkRepository.getVisibleLandmarks(
          minLat,
          minLng,
          maxLat,
          maxLng,
          limit: 250,
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
    } finally {
      _activatingPackId = null;
      notifyListeners();
    }
  }

  Future<void> deactivateRegionPack() async {
    if (_activatingPackId != null || _deactivatingPack) return;
    _deactivatingPack = true;
    notifyListeners();
    try {
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
    } finally {
      _deactivatingPack = false;
      notifyListeners();
    }
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

  /// Start tracking if not already running (safe for auto-start on open).
  void ensureTracking() {
    if (!_isTracking) toggleTracking();
  }

  /// Re-check OS location services / permission and restart GPS if possible.
  Future<bool> retryLocation() async {
    final ok = await _sensors.gpsService.ensureAvailable(
      restartIfReady: _isTracking && _gpsEnabled,
    );
    if (ok && _isTracking && _gpsEnabled) {
      // ensureAvailable may not restart if we weren't marked listening yet.
      _sensors.resumeGps();
    }
    notifyListeners();
    return ok;
  }

  String get gpsStatusMessage => _sensors.gpsService.statusMessage;

  GpsAvailability get gpsAvailability => _sensors.gpsService.availability;

  bool get hasValidPositionFix => _lastFusion?.hasValidFix ?? false;

  /// Live GNSS reading for HUD — null when GPS paused or no fix yet.
  GpsReading? get liveGpsReading {
    if (!_gpsEnabled) return null;
    return _sensors.gpsService.lastReading;
  }

  /// Pause / resume GPS while keeping other sensors live.
  void setGpsEnabled(bool enabled) {
    if (_gpsEnabled == enabled) return;
    _gpsEnabled = enabled;
    if (_isTracking) {
      if (enabled) {
        unawaited(() async {
          await _sensors.gpsService.initialize(requestPermission: false);
          _sensors.resumeGps();
          notifyListeners();
        }());
      } else {
        _sensors.pauseGps();
      }
    }
    _eventLog.addEvent(
      title: enabled ? 'GPS On' : 'GPS Off',
      description: enabled
          ? 'GPS stream resumed.'
          : 'GPS paused — sensors-only tracking (mag / IMU / baro).',
      severity: 'info',
      iconName: enabled ? 'gps_fixed' : 'gps_off',
    );
    notifyListeners();
  }

  /// Leaving the app restores GPS so the next session is not stuck sensors-only.
  void restoreGpsOnLeave() {
    if (!_gpsEnabled) setGpsEnabled(true);
  }

  /// Enable or disable tracking and sensor streams
  void toggleTracking() {
    _isTracking = !_isTracking;
    if (_isTracking) {
      _trail.clear();
      trustTimeline.clear();
      truthMode.clear();
      _spoofAlarmDismissed = false;
      _spoofAlarmVisible = false;
      _sensors.imuService.resetDeadReckoning();
      _sensors.imuService.startListening();
      _sensors.barometerService.startListening();
      _sensors.startAllWithMagAlreadyRunning();

      _sensorSub = _sensors.snapshotStream.listen((snapshot) {
        _processSnapshot(snapshot);
      });

      // Re-init GPS every start — recovers after services/permission were off.
      if (_gpsEnabled) {
        unawaited(() async {
          await _sensors.gpsService.initialize(requestPermission: false);
          if (_isTracking && _gpsEnabled) {
            _sensors.resumeGps();
            notifyListeners();
          }
        }());
      }

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
      // Next start should include GPS unless the user opts out again.
      _gpsEnabled = true;

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
    final gpsReading = _gpsEnabled ? snapshot.gps : null;
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
      gpsUnavailableReason: !_gpsEnabled
          ? 'GPS paused — sensors only'
          : _sensors.gpsService.statusMessage,
    );

    _lastFusion = fusion;
    _opinions = fusion.opinions;
    _trustScore = fusion.confidence;

    // Drop SF (etc.) lock / trail when the device is clearly in another region.
    if (gpsReading != null) {
      if (_landmarkAnchor != null &&
          TrustFusionEngine.isStaleRegionLock(
            lockLat: _landmarkAnchor!.latitude,
            lockLng: _landmarkAnchor!.longitude,
            gpsLat: gpsReading.latitude,
            gpsLng: gpsReading.longitude,
          )) {
        _landmarkAnchor = null;
        _eventLog.addEvent(
          title: 'Real-World Lock Cleared',
          description:
              'Lock was in another region than live GPS — cleared automatically.',
          severity: 'info',
          iconName: 'lock_open',
        );
      }
      if (_trail.isNotEmpty) {
        final last = _trail.last;
        final tLat = last['latitude'];
        final tLng = last['longitude'];
        if (tLat != null &&
            tLng != null &&
            TrustFusionEngine.isStaleRegionLock(
              lockLat: tLat,
              lockLng: tLng,
              gpsLat: gpsReading.latitude,
              gpsLng: gpsReading.longitude,
            )) {
          _trail
            ..clear()
            ..add({
              'latitude': gpsReading.latitude,
              'longitude': gpsReading.longitude,
            });
        }
      }
    }

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

    // Never pollute the trail with a fabricated city when there is no fix.
    if (fusion.hasValidFix) {
      _trail.add({'latitude': fusion.latitude, 'longitude': fusion.longitude});
      _recordTimelineSample(fusion, summary);
    }

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

  /// Export timeline + summary as a court-ready zip evidence vault.
  Future<File> exportEvidencePack() {
    return evidenceExporter.export(
      timeline: trustTimeline,
      lockName: _landmarkAnchor?.name,
      gnssSuspicious: gnssSuspicious,
      lieDistanceM: lieDistanceM,
      brokenWitnesses: _lastFusion?.opinions
              .where((o) => o.status == 'unstable' || o.confidence < 55)
              .map((o) => o.name)
              .toList() ??
          const [],
      meshPeers: witnessMesh.peers.map((p) => p.toJson()).toList(),
      lieEpisodes: truthMode.episodes
          .map(
            (e) => {
              'startedAt': e.startedAt.toUtc().toIso8601String(),
              'endedAt': e.endedAt?.toUtc().toIso8601String(),
              'maxLieDistanceM': e.maxLieDistanceM,
              'claimLat': e.claimLat,
              'claimLng': e.claimLng,
              'trustedLat': e.trustedLat,
              'trustedLng': e.trustedLng,
              'sampleCount': e.sampleCount,
              'ongoing': e.isOngoing,
            },
          )
          .toList(),
    );
  }

  void setTruthModeEnabled(bool enabled) {
    truthMode.setEnabled(enabled);
    if (enabled && truthMode.trustedTrail.isEmpty) {
      truthMode.hydrateFromTimeline(trustTimeline.samples);
    }
    notifyListeners();
  }

  String exportMeshPeerJson() {
    final pos = getTrustedPosition();
    final lat = pos.status != 'unavailable'
        ? pos.latitude
        : liveGpsReading?.latitude ??
            (_trail.isNotEmpty ? _trail.last['latitude'] : null);
    final lng = pos.status != 'unavailable'
        ? pos.longitude
        : liveGpsReading?.longitude ??
            (_trail.isNotEmpty ? _trail.last['longitude'] : null);
    if (lat == null || lng == null) {
      throw StateError('No position to share yet.');
    }
    return witnessMesh.exportLocal(
      deviceId: 'local-${hashCode.abs()}',
      deviceLabel: 'This device',
      latitude: lat,
      longitude: lng,
      accuracyM: liveGpsReading?.accuracy,
      trustScore: _trustScore,
      gnssSuspicious: gnssSuspicious,
      lockName: _landmarkAnchor?.name,
    );
  }

  MeshCompareResult? importMeshPeerJson(String raw) {
    final pos = getTrustedPosition();
    final lat = pos.status != 'unavailable'
        ? pos.latitude
        : liveGpsReading?.latitude ??
            (_trail.isNotEmpty ? _trail.last['latitude'] : null);
    final lng = pos.status != 'unavailable'
        ? pos.longitude
        : liveGpsReading?.longitude ??
            (_trail.isNotEmpty ? _trail.last['longitude'] : null);
    if (lat == null || lng == null) return null;
    final result = witnessMesh.importPeer(
      raw,
      localLat: lat,
      localLng: lng,
      localSuspicious: gnssSuspicious,
    );
    if (result != null) {
      _eventLog.addEvent(
        title: 'Witness Mesh',
        description: result.headline,
        severity: result.verdict == 'agree' ? 'info' : 'warning',
        iconName: 'devices',
      );
      notifyListeners();
    }
    return result;
  }

  List<SpoofHeatCell> get spoofHeatCells => spoofHeatmap.build(
        samples: trustTimeline.samples,
        includeDemo: true,
      );

  TrustAdvisory? get currentAdvisory {
    final summary = TrustSummary.fromOpinions(
      trustScore: _trustScore,
      opinions: _opinions,
      isTracking: _isTracking,
      gnssSuspicious: gnssSuspicious,
    );
    return trustCopilot.advise(
      summary: summary,
      opinions: _opinions,
      isTracking: _isTracking,
      gpsEnabled: _gpsEnabled,
      hasGpsFix: hasValidPositionFix,
      gnssSuspicious: gnssSuspicious,
      hasLock: hasRealWorldLock,
      hasActivePack: activePackId.isNotEmpty,
      lieDistanceM: lieDistanceM,
    );
  }

  List<RegionPack> get missionPacks =>
      packs.where((p) => p.isMissionPack).toList();

  /// One-tap mission: activate if installed, else begin download.
  Future<void> launchMissionPack(RegionPack pack) async {
    if (pack.status == 'downloaded' ||
        pack.localPath != null ||
        pack.checksum == 'bundled-demo') {
      await activateRegionPack(pack.id);
      return;
    }
    await regionRepository.startDownload(pack.id);
  }

  /// Snap to demo geometry kinds and lock as Real World anchor.
  Future<Landmark?> lockToGeometry({required String kind}) async {
    final gps = _sensors.gpsService.lastReading;
    final lat = gps?.latitude ??
        (_trail.isNotEmpty ? _trail.last['latitude'] : null);
    final lng = gps?.longitude ??
        (_trail.isNotEmpty ? _trail.last['longitude'] : null);
    // Do not invent a city to snap against — need a real fix or trail.
    if (lat == null || lng == null) return null;

    final snap = kind == 'nearest'
        ? await geometrySnap.snapNearest(lat, lng)
        : await geometrySnap.snap(kind, lat, lng);
    if (snap == null) return null;

    final landmark = Landmark.legacy(
      name: snap.label,
      latitude: snap.latitude,
      longitude: snap.longitude,
      confidence: 0.92,
      saved: true,
      type: snap.kind,
    );
    setLandmarkAnchor(landmark, 92);
    return landmark;
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
        gpsClaimLatitude: fusion.gpsClaimLatitude,
        gpsClaimLongitude: fusion.gpsClaimLongitude,
        trustedLatitude: fusion.latitude,
        trustedLongitude: fusion.longitude,
        lieDistanceM: fusion.lieDistanceM,
      ),
    );

    truthMode.record(
      gnssSuspicious: fusion.gnssSuspicious,
      trustedLat: fusion.latitude,
      trustedLng: fusion.longitude,
      claimLat: fusion.gpsClaimLatitude,
      claimLng: fusion.gpsClaimLongitude,
      lieDistanceM: fusion.lieDistanceM,
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
      final whami = getPositionOpinions().firstWhere(
        (o) => o.sourceType == 'whami' && o.status != 'unavailable',
      );
      if (_lastFusion != null && !_lastFusion!.hasValidFix) {
        return PositionOpinion.unavailable(
          id: 'whami',
          name: 'WHAMI Trusted Position',
          shortCode: 'W',
          sourceType: 'whami',
          colorName: 'amber',
          description: 'No position fix yet',
        );
      }
      return whami;
    } catch (_) {
      if (_trail.isNotEmpty) {
        return PositionOpinion.whami(
          latitude: _trail.last['latitude']!,
          longitude: _trail.last['longitude']!,
          confidence: _trustScore,
          uncertaintyRadius: 30,
          description: _alertMessage,
        );
      }
      return PositionOpinion.unavailable(
        id: 'whami',
        name: 'WHAMI Trusted Position',
        shortCode: 'W',
        sourceType: 'whami',
        colorName: 'amber',
        description: 'No position fix yet',
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
          description: !_gpsEnabled
              ? 'GPS paused — sensors only'
              : _sensors.gpsService.statusMessage,
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
