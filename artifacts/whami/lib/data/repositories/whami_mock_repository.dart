import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/connectivity_status.dart';
import '../mock/mock_position_data.dart';
import '../mock/mock_sensor_data.dart';
import '../mock/mock_alert_data.dart';
import '../mock/mock_region_pack_data.dart';
import '../mock/region_pack_cdn.dart';
import '../models/position_opinion.dart';
import '../models/sensor_status.dart';
import '../models/region_pack.dart';
import '../models/trust_scenario.dart';
import '../models/trust_event.dart';

class Landmark {
  final String name;
  final double latitude;
  final double longitude;
  final double confidence;
  final bool saved;

  const Landmark({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.saved,
  });
}

/// Central mock repository — handles downloads, tracking, and regional shifts.
class WhamiMockRepository extends ChangeNotifier {
  // ── Scenario state ─────────────────────────────────────────────────────────
  int _scenarioIndex = 0;
  List<PositionOpinion> _activeOpinions = [];
  int? _liveTrustScore;
  int _tickCount = 0;

  // Active pack state
  String _activePackId = 'sf_bay';
  String get activePackId => _activePackId;

  // Map center override for centering on specific landmarks
  double? mapCenterLat;
  double? mapCenterLng;

  void centerMapOn(double lat, double lng) {
    mapCenterLat = lat;
    mapCenterLng = lng;
    notifyListeners();
  }

  void activateRegionPack(String packId) {
    if (_activePackId == packId) return;

    // De-activate other packs in status
    final packIndex = _packs.indexWhere((p) => p.id == packId);
    if (packIndex == -1 || _packs[packIndex].status != 'downloaded') return;

    _activePackId = packId;

    // Shift opinion coordinates to center on the activated pack
    final newCenter =
        RegionPackCdn.centers[packId] ?? RegionPackCdn.centers['sf_bay']!;
    final baseScenarioOpinions = activeScenario.opinions;
    _activeOpinions = baseScenarioOpinions.map((op) {
      final double deltaLat = op.latitude - 37.8087;
      final double deltaLng = op.longitude - (-122.4098);
      return PositionOpinion(
        id: op.id,
        name: op.name,
        shortCode: op.shortCode,
        sourceType: op.sourceType,
        latitude: newCenter.$1 + deltaLat,
        longitude: newCenter.$2 + deltaLng,
        confidence: op.confidence,
        uncertaintyRadius: op.uncertaintyRadius,
        colorName: op.colorName,
        status: op.status,
        description: op.description,
      );
    }).toList();

    _liveTrustScore = null;
    _trail.clear();

    // Center map view on new pack center
    centerMapOn(newCenter.$1, newCenter.$2);

    notifyListeners();
  }

  List<TrustScenario> get scenarios => MockPositionData.scenarios;
  TrustScenario get activeScenario => scenarios[_scenarioIndex];

  void setScenario(int index) {
    if (index >= 0 && index < scenarios.length) {
      _scenarioIndex = index;

      // Shift scenario opinions to current active pack
      final newCenter =
          RegionPackCdn.centers[_activePackId] ??
          RegionPackCdn.centers['sf_bay']!;
      _activeOpinions = scenarios[_scenarioIndex].opinions.map((op) {
        final double deltaLat = op.latitude - 37.8087;
        final double deltaLng = op.longitude - (-122.4098);
        return PositionOpinion(
          id: op.id,
          name: op.name,
          shortCode: op.shortCode,
          sourceType: op.sourceType,
          latitude: newCenter.$1 + deltaLat,
          longitude: newCenter.$2 + deltaLng,
          confidence: op.confidence,
          uncertaintyRadius: op.uncertaintyRadius,
          colorName: op.colorName,
          status: op.status,
          description: op.description,
        );
      }).toList();

      _liveTrustScore = null;
      _trail.clear();
      notifyListeners();
    }
  }

  // ── Connectivity state ─────────────────────────────────────────────────────
  ConnectivityMode _connectivityMode = ConnectivityMode.offline;

  ConnectivityMode get connectivityMode => _connectivityMode;

  set connectivityMode(ConnectivityMode mode) {
    if (_connectivityMode != mode) {
      _connectivityMode = mode;
      _liveTrustScore = null;
      notifyListeners();
    }
  }

  // ── Positions & Live tracking simulation ──────────────────────────────────
  bool _isTracking = false;
  Timer? _trackingTimer;
  final List<dynamic> _trail = [];

  bool get isTracking => _isTracking;
  List<dynamic> get trail => _trail;

  void toggleTracking() {
    _isTracking = !_isTracking;
    if (_isTracking) {
      final currentPos = getTrustedPosition();
      _trail.add({
        'latitude': currentPos.latitude,
        'longitude': currentPos.longitude,
      });
      _tickCount = 0;
      _trackingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _simulateStep();
      });
    } else {
      _trackingTimer?.cancel();
      _trackingTimer = null;
    }
    notifyListeners();
  }

  void _simulateStep() {
    _tickCount++;
    final double latOffset = 0.00015 * sin(_tickCount * 0.15);
    final double lngOffset = 0.00025 * cos(_tickCount * 0.15);

    final baseOpinions = getPositionOpinions();
    final updated = <PositionOpinion>[];

    for (final op in baseOpinions) {
      if (op.confidence == 0) {
        updated.add(op);
        continue;
      }

      double jitterLat = 0;
      double jitterLng = 0;
      if (op.sourceType == 'gps') {
        jitterLat = (Random().nextDouble() - 0.5) * 0.0001;
        jitterLng = (Random().nextDouble() - 0.5) * 0.0001;
      } else if (op.sourceType == 'magnetic' || op.sourceType == 'sextant') {
        jitterLat = (Random().nextDouble() - 0.5) * 0.00015;
        jitterLng = (Random().nextDouble() - 0.5) * 0.00015;
      }

      updated.add(
        PositionOpinion(
          id: op.id,
          name: op.name,
          shortCode: op.shortCode,
          sourceType: op.sourceType,
          latitude: op.latitude + latOffset + jitterLat,
          longitude: op.longitude + lngOffset + jitterLng,
          confidence: op.confidence,
          uncertaintyRadius: op.uncertaintyRadius,
          colorName: op.colorName,
          status: op.status,
          description: op.description,
        ),
      );
    }

    _activeOpinions = updated;

    final whamiPos = getTrustedPosition();
    _trail.add({
      'latitude': whamiPos.latitude,
      'longitude': whamiPos.longitude,
    });

    final baseTrust = activeScenario.trustScore;
    _liveTrustScore = (baseTrust + (Random().nextInt(5) - 2)).clamp(0, 100);

    notifyListeners();
  }

  List<PositionOpinion> getPositionOpinions() {
    if (_activeOpinions.isEmpty) {
      // Shift base scenario opinions to current pack on demand
      final newCenter =
          RegionPackCdn.centers[_activePackId] ??
          RegionPackCdn.centers['sf_bay']!;
      _activeOpinions = activeScenario.opinions.map((op) {
        final double deltaLat = op.latitude - 37.8087;
        final double deltaLng = op.longitude - (-122.4098);
        return PositionOpinion(
          id: op.id,
          name: op.name,
          shortCode: op.shortCode,
          sourceType: op.sourceType,
          latitude: newCenter.$1 + deltaLat,
          longitude: newCenter.$2 + deltaLng,
          confidence: op.confidence,
          uncertaintyRadius: op.uncertaintyRadius,
          colorName: op.colorName,
          status: op.status,
          description: op.description,
        );
      }).toList();
    }

    if (_connectivityMode == ConnectivityMode.limited) {
      return _activeOpinions.map((op) {
        if (op.sourceType == 'gps') {
          return op;
        } else if (op.sourceType == 'whami') {
          return PositionOpinion(
            id: op.id,
            name: op.name,
            shortCode: op.shortCode,
            sourceType: op.sourceType,
            latitude: op.latitude,
            longitude: op.longitude,
            confidence: 35,
            uncertaintyRadius: 180,
            colorName: op.colorName,
            status: 'active',
            description: 'GPS only - no consensus verification available',
          );
        } else {
          return PositionOpinion(
            id: op.id,
            name: op.name,
            shortCode: op.shortCode,
            sourceType: op.sourceType,
            latitude: op.latitude,
            longitude: op.longitude,
            confidence: 0,
            uncertaintyRadius: 0,
            colorName: op.colorName,
            status: 'unavailable',
            description: 'Sensor offline - no region pack coverage',
          );
        }
      }).toList();
    }

    return _activeOpinions;
  }

  PositionOpinion getTrustedPosition() {
    try {
      return getPositionOpinions().firstWhere((o) => o.sourceType == 'whami');
    } catch (_) {
      return getPositionOpinions().first;
    }
  }

  int getTrustScore() {
    if (_connectivityMode == ConnectivityMode.limited) {
      return 35;
    }
    return _liveTrustScore ?? activeScenario.trustScore;
  }

  String getAlertMessage() {
    if (_connectivityMode == ConnectivityMode.limited) {
      return 'LIMITED connectivity. Downloading a region pack is required to unlock full WHAMI trust.';
    }
    return activeScenario.alertMessage;
  }

  // ── Sensors ────────────────────────────────────────────────────────────────
  List<SensorStatus> getSensorStatuses() {
    if (_connectivityMode == ConnectivityMode.limited) {
      return activeScenario.sensors.map((s) {
        if (s.name.toLowerCase().contains('gps') ||
            s.name.toLowerCase().contains('satellite')) {
          return s;
        }
        return s.copyWith(
          status: 'Offline',
          confidence: 0,
          latestValue: 'Offline',
          healthMessage: 'Sensor offline - no region pack coverage',
        );
      }).toList();
    }
    return activeScenario.sensors;
  }

  // ── Region packs & Download flow ───────────────────────────────────────────
  final List<RegionPack> _packs = List.from(MockRegionPackData.packs);
  final Map<String, dynamic> _activeDownloads = {};
  final Map<String, String> _originalStatuses = {};

  List<RegionPack> getRegionPacks() => _packs;

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

  void startDownload(String packId) async {
    if (_activeDownloads.containsKey(packId)) return;

    final index = _packs.indexWhere((p) => p.id == packId);
    if (index == -1) return;

    final originalStatus = _packs[index].status;
    _originalStatuses[packId] = originalStatus;

    // Initialize download state
    _packs[index] = _packs[index].copyWith(
      status: 'downloading',
      isDownloading: true,
      downloadProgress: 0.0,
      downloadStage: 'Connecting to mock CDN server...',
    );
    notifyListeners();

    // Perform a real network request using http package
    final client = http.Client();
    bool useFallback = false;
    StreamSubscription? subscription;

    try {
      // Drip 500 bytes over 3 seconds to simulate progress
      final request = http.Request(
        'GET',
        Uri.parse('https://httpbin.org/drip?numbytes=500&duration=3&delay=0'),
      );
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 4));

      int bytesReceived = 0;
      const totalBytes = 500;

      final sub = response.stream.listen(
        (chunk) {
          bytesReceived += chunk.length;
          double progress = (bytesReceived / totalBytes).clamp(0.0, 1.0);

          String stage = 'Downloading files...';
          if (progress <= 0.40) {
            stage = 'Downloading map tiles...';
          } else if (progress <= 0.60) {
            stage = 'Downloading landmarks...';
          } else if (progress <= 0.80) {
            stage = 'Downloading magnetic grid...';
          } else if (progress <= 0.95) {
            stage = 'Downloading sea charts...';
          } else {
            stage = 'Verifying integrity...';
          }

          final idx = _packs.indexWhere((p) => p.id == packId);
          if (idx != -1) {
            _packs[idx] = _packs[idx].copyWith(
              downloadProgress: progress,
              downloadStage: stage,
            );
            debugPrint('Download progress for pack $packId: $progress');
            debugPrint('Download stage for pack $packId: $stage');
            debugPrint(
              'Download bytes received for pack $packId: $bytesReceived',
            );
            debugPrint('Download total bytes for pack $packId: $totalBytes');
            debugPrint(
              'Download bytes received for pack $packId: $bytesReceived',
            );
            notifyListeners();
          }
        },
        onDone: () {
          debugPrint('Download completed for pack $packId');
          _completeDownload(packId);
          client.close();
        },
        onError: (e) {
          debugPrint('Error downloading pack $packId: $e');
          _runDownloadFallback(packId);
          client.close();
        },
        cancelOnError: true,
      );
      debugPrint('Download started for pack $packId');
      debugPrint('Subscription: ${sub.toString()}');
      _activeDownloads[packId] = sub;
    } catch (e) {
      _runDownloadFallback(packId);
      client.close();
    }
  }

  void _runDownloadFallback(String packId) {
    double progress = 0.0;
    final timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      progress += 0.05;
      if (progress >= 1.0) {
        t.cancel();
        _completeDownload(packId);
      } else {
        String stage = 'Connecting to server...';
        if (progress <= 0.40) {
          stage = 'Downloading map tiles...';
        } else if (progress <= 0.60) {
          stage = 'Downloading landmarks...';
        } else if (progress <= 0.80) {
          stage = 'Downloading magnetic grid...';
        } else if (progress <= 0.95) {
          stage = 'Downloading sea charts...';
        } else {
          stage = 'Verifying integrity...';
        }
        final idx = _packs.indexWhere((p) => p.id == packId);
        if (idx != -1) {
          _packs[idx] = _packs[idx].copyWith(
            downloadProgress: progress,
            downloadStage: stage,
          );
          notifyListeners();
        }
      }
    });
    _activeDownloads[packId] = timer;
  }

  void _completeDownload(String packId) {
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index == -1) return;

    _packs[index] = _packs[index].copyWith(
      status: 'downloaded',
      isDownloading: false,
      downloadProgress: 1.0,
      downloadStage: 'Verifying integrity...',
    );
    notifyListeners();

    _activeDownloads.remove(packId);

    Future.delayed(const Duration(milliseconds: 400), () {
      final idx = _packs.indexWhere((p) => p.id == packId);
      if (idx != -1 && _packs[idx].status == 'downloaded') {
        _packs[idx] = _packs[idx].copyWith(
          isDownloading: false,
          downloadProgress: 0.0,
          downloadStage: '',
        );
        notifyListeners();
      }
    });
  }

  void cancelDownload(String packId) {
    final task = _activeDownloads[packId];
    if (task != null) {
      if (task is StreamSubscription) {
        task.cancel();
      } else if (task is Timer) {
        task.cancel();
      }
      _activeDownloads.remove(packId);
    }

    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      final originalStatus = _originalStatuses[packId] ?? 'available';
      _packs[index] = _packs[index].copyWith(
        status: originalStatus,
        isDownloading: false,
        downloadProgress: 0.0,
        downloadStage: '',
      );
      notifyListeners();
    }
  }

  void deleteRegionPack(String packId) {
    cancelDownload(packId);
    final index = _packs.indexWhere((p) => p.id == packId);
    if (index != -1) {
      final String targetStatus = packId == 'mountain_view'
          ? 'update_needed'
          : 'available';
      _packs[index] = _packs[index].copyWith(
        status: targetStatus,
        isDownloading: false,
        downloadProgress: 0.0,
        downloadStage: '',
      );
      if (_activePackId == packId) {
        _activePackId = 'sf_bay'; // Fallback to sf_bay
      }
      notifyListeners();
    }
  }

  // ── Landmark helpers ───────────────────────────────────────────────────────
  List<Landmark> getLandmarks() {
    final list = RegionPackCdn.landmarksByRegion[_activePackId] ?? [];
    return list
        .map(
          (item) => Landmark(
            name: item.$1,
            latitude: item.$2,
            longitude: item.$3,
            confidence: 0.90,
            saved: item.$4,
          ),
        )
        .toList();
  }

  Landmark? findNearestLandmark(double lat, double lng) {
    final list = getLandmarks();
    if (list.isEmpty) return null;
    Landmark nearest = list.first;
    double minDistance = _distanceSq(
      lat,
      lng,
      nearest.latitude,
      nearest.longitude,
    );
    for (final landmark in list) {
      final d = _distanceSq(lat, lng, landmark.latitude, landmark.longitude);
      if (d < minDistance) {
        minDistance = d;
        nearest = landmark;
      }
    }
    return nearest;
  }

  double _distanceSq(double lat1, double lng1, double lat2, double lng2) {
    final dLat = lat1 - lat2;
    final dLng = lng1 - lng2;
    return dLat * dLat + dLng * dLng;
  }

  // ── Trust events ───────────────────────────────────────────────────────────
  List<TrustEvent> getTrustEvents() => MockAlertData.events;

  // ── Trust breakdown ────────────────────────────────────────────────────────
  Map<String, dynamic> getTrustBreakdown() {
    final opinions = getPositionOpinions();

    int landmarkConf = _confidenceFor(opinions, 'landmark');
    int gpsConf = _confidenceFor(opinions, 'gps');
    int magConf = _confidenceFor(opinions, 'magnetic');
    int imuConf = _confidenceFor(opinions, 'imu');
    int skyConf = _confidenceFor(opinions, 'sextant');

    final score =
        (0.45 * landmarkConf +
                0.20 * gpsConf +
                0.15 * magConf +
                0.10 * imuConf +
                0.10 * skyConf)
            .round();

    return {
      'landmarkMatch': landmarkConf,
      'gpsConfidence': gpsConf,
      'magneticFit': magConf,
      'imuPath': imuConf,
      'skyStability': skyConf,
      'finalScore': score,
    };
  }

  int _confidenceFor(List<PositionOpinion> opinions, String sourceType) {
    try {
      return opinions.firstWhere((o) => o.sourceType == sourceType).confidence;
    } catch (_) {
      return 0;
    }
  }

  List<SensorStatus> get defaultSensors => MockSensorData.normalSensors;

  @override
  void dispose() {
    _trackingTimer?.cancel();
    for (final task in _activeDownloads.values) {
      if (task is StreamSubscription) {
        task.cancel();
      } else if (task is Timer) {
        task.cancel();
      }
    }
    super.dispose();
  }
}
