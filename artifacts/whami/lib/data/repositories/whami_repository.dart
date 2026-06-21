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
import '../services/region_pack_storage.dart';
import '../services/region_pack_downloader.dart';
import '../services/position_matcher.dart';
import '../services/trust_fusion_engine.dart';
import '../services/trust_event_log.dart';

class WhamiRepository extends ChangeNotifier {
  final SensorManager _sensors;
  final RegionPackStorage _storage;
  final RegionPackDownloader _downloader;
  final PositionMatcher _matcher;
  final TrustFusionEngine _fusionEngine;
  final TrustEventLog _eventLog;

  // Live navigation state
  List<PositionOpinion> _opinions = [];
  int _trustScore = 75;
  String _alertMessage = 'Positions aligned. System nominal.';
  String _alertSeverity = 'none';
  bool _isTracking = false;
  final List<Map<String, double>> _trail = [];

  // Active pack state
  String _activePackId = '';
  Map<String, dynamic>? _loadedLandmarks;
  Map<String, dynamic>? _loadedMagnetic;
  Map<String, dynamic>? _loadedSeamap;

  // Connectivity state
  ConnectivityMode _connectivityMode = ConnectivityMode.offline;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Region Packs metadata catalog
  final List<RegionPack> _packs = [];

  // Stream Subscriptions
  StreamSubscription? _sensorSub;
  StreamSubscription<DownloadProgress>? _downloadSub;

  // Map center overrides (optional)
  double? mapCenterLat;
  double? mapCenterLng;

  // Getters
  SensorManager get sensors => _sensors;
  RegionPackStorage get storage => _storage;
  RegionPackDownloader get downloader => _downloader;
  TrustEventLog get eventLog => _eventLog;

  List<PositionOpinion> get positionOpinions => _opinions;
  int get trustScore => _trustScore;
  String get alertMessage => _alertMessage;
  String get alertSeverity => _alertSeverity;
  bool get isTracking => _isTracking;
  List<Map<String, double>> get trail => _trail;
  String get activePackId => _activePackId;
  ConnectivityMode get connectivityMode => _connectivityMode;

  ConnectivityState get connectivityState {
    final activePack = getRegionPackById(_activePackId);
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
    required RegionPackStorage storage,
    required RegionPackDownloader downloader,
    required PositionMatcher matcher,
    required TrustFusionEngine fusionEngine,
    required TrustEventLog eventLog,
  })  : _sensors = sensors,
        _storage = storage,
        _downloader = downloader,
        _matcher = matcher,
        _fusionEngine = fusionEngine,
        _eventLog = eventLog {
    _initCatalog();
    _initConnectivity();
    _subscribeToDownloads();
  }

  /// Initialize region pack list and cross-check filesystem status
  Future<void> _initCatalog() async {
    // Pre-populate catalog using similar details as mock data
    final defaultPacks = [
      RegionPack(
        id: 'sf_bay',
        name: 'SF Bay Harbor Pack',
        type: 'Marine',
        size: '142 MB',
        status: 'available',
        location: 'San Francisco Bay, CA',
        lastUpdated: 'Jun 10, 2026',
        includedData: const ['Land maps', 'Marine data', 'Landmarks (847)', 'Magnetic baseline', 'Celestial tables', 'Route trust history'],
        trustScore: 94,
        fileSizes: const {
          'maps': '98.4 MB (847 tiles)',
          'marine': '17.0 MB (sea charts)',
          'landmarks': '14.2 MB (847 points)',
          'magnetic': '8.1 MB (2,500 grid pts)',
          'celestial': '4.3 MB (star catalog)',
        },
      ),
      RegionPack(
        id: 'tahoe',
        name: 'Lake Tahoe Pack',
        type: 'Lake',
        size: '88 MB',
        status: 'available',
        location: 'Lake Tahoe, CA/NV',
        lastUpdated: 'May 28, 2026',
        includedData: const ['Land maps', 'Lake data', 'Landmarks (312)', 'Magnetic baseline', 'Celestial tables'],
        trustScore: 89,
        fileSizes: const {
          'maps': '56.1 MB (412 tiles)',
          'marine': '12.4 MB (lake contours)',
          'landmarks': '5.2 MB (312 points)',
          'magnetic': '9.8 MB (1,800 grid pts)',
          'celestial': '4.5 MB (star catalog)',
        },
      ),
      RegionPack(
        id: 'mountain_view',
        name: 'Mountain View Hiking Pack',
        type: 'Hiking',
        size: '64 MB',
        status: 'available',
        location: 'Santa Cruz Mountains, CA',
        lastUpdated: 'Mar 15, 2026',
        includedData: const ['Land maps', 'Trail data', 'Landmarks (198)', 'Magnetic baseline', 'Celestial tables', 'IMU path templates'],
        trustScore: 76,
        fileSizes: const {
          'maps': '38.2 MB (284 tiles)',
          'marine': '4.1 MB (trail contours)',
          'landmarks': '3.3 MB (198 points)',
          'magnetic': '5.4 MB (900 grid pts)',
          'celestial': '4.5 MB (star catalog)',
          'imu': '8.5 MB (path templates)',
        },
      ),
      RegionPack(
        id: 'rotterdam',
        name: 'Rotterdam Harbor Pack',
        type: 'Marine',
        size: '210 MB',
        status: 'available',
        location: 'Port of Rotterdam, Netherlands',
        lastUpdated: 'Jun 1, 2026',
        includedData: const ['Land maps', 'Marine data', 'Landmarks (1,204)', 'Magnetic baseline', 'Celestial tables', 'Route trust history', 'Harbor lane data'],
        trustScore: 97,
        fileSizes: const {
          'maps': '124.5 MB (1,204 tiles)',
          'marine': '36.8 MB (channel depths)',
          'landmarks': '22.3 MB (1,204 points)',
          'magnetic': '12.2 MB (3,600 grid pts)',
          'celestial': '4.5 MB (star catalog)',
          'trust': '9.7 MB (route histories)',
        },
      ),
      RegionPack(
        id: 'coastal_demo',
        name: 'Coastal Emergency Demo Pack',
        type: 'Urban',
        size: '38 MB',
        status: 'available',
        location: 'Demo — Coastal Area',
        lastUpdated: 'Jun 14, 2026',
        includedData: const ['Land maps', 'Coastal data', 'Landmarks (56)', 'Magnetic baseline', 'Celestial tables'],
        trustScore: 82,
        fileSizes: const {
          'maps': '24.1 MB (156 tiles)',
          'marine': '5.2 MB (depth contours)',
          'landmarks': '1.8 MB (56 points)',
          'magnetic': '2.4 MB (300 grid pts)',
        },
      ),
    ];

    _packs.clear();
    _packs.addAll(defaultPacks);

    // Sync statuses against local storage
    for (int i = 0; i < _packs.length; i++) {
      final isDownloaded = await _storage.isPackDownloaded(_packs[i].id);
      if (isDownloaded) {
        _packs[i] = _packs[i].copyWith(status: 'downloaded');
      }
    }

    // Default active pack is first downloaded one
    final downloaded = _packs.firstWhere((p) => p.status == 'downloaded', orElse: () => _packs.first);
    if (downloaded.status == 'downloaded') {
      await activateRegionPack(downloaded.id);
    } else {
      // Fallback
      _activePackId = '';
    }

    _eventLog.seedInitialEvents();
    notifyListeners();
  }

  /// Auto detect network connectivity using connectivity_plus
  void _initConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final activePack = getRegionPackById(_activePackId);
      final packName = activePack?.name ?? 'No Pack';
      final hasPack = activePack != null && activePack.status == 'downloaded';
      final status = hasPack ? 'Active' : 'Not Loaded';

      final state = ConnectivityState.fromResults(
        results,
        activePackName: packName,
        packCoverageStatus: status,
      );
      _connectivityMode = state.mode;
      notifyListeners();
    });
  }

  set connectivityMode(ConnectivityMode mode) {
    if (_connectivityMode != mode) {
      _connectivityMode = mode;
      notifyListeners();
    }
  }

  /// Connect downloader streams to repository list updates
  void _subscribeToDownloads() {
    _downloadSub = _downloader.progressStream.listen((progressEvent) {
      final index = _packs.indexWhere((p) => p.id == progressEvent.packId);
      if (index != -1) {
        final pack = _packs[index];
        if (progressEvent.status == 'completed') {
          _packs[index] = pack.copyWith(
            status: 'downloaded',
            isDownloading: false,
            downloadProgress: 1.0,
            downloadStage: 'Complete',
          );
          _eventLog.addEvent(
            title: 'Region Pack Downloaded',
            description: 'Pack ${pack.name} is now available offline.',
            severity: 'info',
            iconName: 'download_done',
          );
          // If no active pack, activate this one
          if (_activePackId.isEmpty) {
            activateRegionPack(pack.id);
          }
        } else if (progressEvent.status == 'failed') {
          _packs[index] = pack.copyWith(
            status: 'available',
            isDownloading: false,
            downloadProgress: 0.0,
            downloadStage: 'Failed: ${progressEvent.error}',
          );
          _eventLog.addEvent(
            title: 'Download Failed',
            description: 'Failed to download ${pack.name}: ${progressEvent.error}',
            severity: 'warning',
            iconName: 'error',
          );
        } else {
          _packs[index] = pack.copyWith(
            status: 'downloading',
            isDownloading: true,
            downloadProgress: progressEvent.progress,
            downloadStage: 'Downloading (${(progressEvent.progress * 100).toStringAsFixed(0)}%)',
          );
        }
        notifyListeners();
      }
    });
  }

  /// Start download flow via downloader service
  void startDownload(String packId) {
    final pack = getRegionPackById(packId);
    if (pack != null && pack.status != 'downloaded') {
      _downloader.startDownload(pack);
    }
  }

  void cancelDownload(String packId) {
    //
  }

  /// Delete a region pack from disk and update list status
  Future<void> deleteRegionPack(String packId) async {
    await _storage.deletePackFiles(packId);
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(status: 'available');
    }
    if (_activePackId == packId) {
      _activePackId = '';
      _loadedLandmarks = null;
      _loadedMagnetic = null;
      _loadedSeamap = null;
    }
    _eventLog.addEvent(
      title: 'Region Pack Removed',
      description: 'Pack files deleted from device storage.',
      severity: 'info',
      iconName: 'delete',
    );
    notifyListeners();
  }

  /// Set the active region pack and load its GeoJSON data from storage
  Future<void> activateRegionPack(String packId) async {
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index == -1 || _packs[index].status != 'downloaded') return;

    _activePackId = packId;

    try {
      _loadedLandmarks = await _storage.loadGeoJson(packId, 'landmarks.geojson');
      _loadedMagnetic = await _storage.loadGeoJson(packId, 'magnetic.geojson');
      _loadedSeamap = await _storage.loadGeoJson(packId, 'seamap.geojson');

      // Get pack center to focus map
      final manifest = await _storage.getPackManifest(packId);
      if (manifest != null) {
        final double centerLat = manifest['center_latitude'] as double? ?? 37.8087;
        final double centerLng = manifest['center_longitude'] as double? ?? -122.4098;
        centerMapOn(centerLat, centerLng);
      }

      _eventLog.addEvent(
        title: 'Region Activated',
        description: 'Loaded ${packs[index].name} datasets locally.',
        severity: 'info',
        iconName: 'map',
      );
    } catch (e) {
      debugPrint('Error activating region pack $packId: $e');
      _eventLog.addEvent(
        title: 'Activation Failed',
        description: 'Failed to load pack GeoJSON layers.',
        severity: 'critical',
        iconName: 'error_outline',
      );
    }

    notifyListeners();
  }

  /// Enable or disable tracking and start/stop the hardware streams
  void toggleTracking() {
    _isTracking = !_isTracking;
    if (_isTracking) {
      _trail.clear();
      _sensors.imuService.resetDeadReckoning();
      _sensors.startAll();

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
      _sensors.stopAll();

      _eventLog.addEvent(
        title: 'Tracking Stopped',
        description: 'Sensor streams closed.',
        severity: 'info',
        iconName: 'stop',
      );
    }
    notifyListeners();
  }

  /// Process live sensor readings through matchers and fusion algorithm
  void _processSnapshot(SensorSnapshot snapshot) {
    final gpsReading = snapshot.gps;
    final magReading = snapshot.magnetometer;

    LandmarkMatch? lMatch;
    MagneticMatch? mMatch;
    SeamapMatch? sMatch;

    if (gpsReading != null) {
      lMatch = _matcher.matchLandmarks(
        latitude: gpsReading.latitude,
        longitude: gpsReading.longitude,
        landmarksGeoJson: _loadedLandmarks,
      );

      if (magReading != null) {
        mMatch = _matcher.matchMagnetic(
          latitude: gpsReading.latitude,
          longitude: gpsReading.longitude,
          liveStrength: magReading.fieldStrength,
          magneticGeoJson: _loadedMagnetic,
        );
      }

      sMatch = _matcher.matchSeamap(
        latitude: gpsReading.latitude,
        longitude: gpsReading.longitude,
        seamapGeoJson: _loadedSeamap,
      );
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
      hasOfflineData: _activePackId.isNotEmpty,
      lastTrustedLat: lastLat,
      lastTrustedLng: lastLng,
    );

    _opinions = fusion.opinions;
    _trustScore = fusion.confidence;

    // Track state change to trigger event log notification
    if (fusion.alertSeverity != _alertSeverity && fusion.alertSeverity != 'none') {
      _eventLog.addEvent(
        title: 'Fusion Status Change',
        description: fusion.alertMessage,
        severity: fusion.alertSeverity,
        iconName: 'warning',
      );
    }

    _alertMessage = fusion.alertMessage;
    _alertSeverity = fusion.alertSeverity;

    // Record trail point
    _trail.add({
      'latitude': fusion.latitude,
      'longitude': fusion.longitude,
    });

    notifyListeners();
  }

  void centerMapOn(double lat, double lng) {
    mapCenterLat = lat;
    mapCenterLng = lng;
    notifyListeners();
  }

  List<RegionPack> getRegionPacks() => _packs;

  List<RegionPack> get packs => _packs;

  RegionPack? getRegionPackById(String id) {
    try {
      return _packs.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  void updatePackStatus(String id, String status) {
    final index = _packs.indexWhere((p) => p.id == id);
    if (index != -1) {
      _packs[index] = _packs[index].copyWith(status: status);
      notifyListeners();
    }
  }

  PositionOpinion getTrustedPosition() {
    try {
      return getPositionOpinions().firstWhere((o) => o.sourceType == 'whami');
    } catch (_) {
      // Create a live trusted coordinate point if whami isn't compiled
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
      // Build dummy loading opinions before tracking starts
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
        latestValue: _isTracking ? 'Consensus confidence: $_trustScore%' : 'Ready',
        healthMessage: _alertMessage,
        iconName: 'security',
        lastUpdated: DateTime.now(),
      ),
    );
    return list;
  }

  List<TrustEvent> getTrustEvents() {
    return _eventLog.getEvents();
  }

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

  List<Landmark> getLandmarks() {
    if (_loadedLandmarks == null) return [];
    final features = _loadedLandmarks!['features'] as List<dynamic>?;
    if (features == null) return [];

    return features.map((f) {
      final geom = f['geometry'] as Map<String, dynamic>;
      final coords = geom['coordinates'] as List<dynamic>;
      final props = f['properties'] as Map<String, dynamic>;
      return Landmark(
        name: props['name'] as String? ?? 'Unnamed',
        latitude: (coords[1] as num).toDouble(),
        longitude: (coords[0] as num).toDouble(),
        confidence: (props['confidence'] as num?)?.toDouble() ?? 0.8,
        saved: props['saved'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _sensorSub?.cancel();
    _downloadSub?.cancel();
    super.dispose();
  }
}
