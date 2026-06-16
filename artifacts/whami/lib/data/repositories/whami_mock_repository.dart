import '../mock/mock_position_data.dart';
import '../mock/mock_sensor_data.dart';
import '../mock/mock_alert_data.dart';
import '../mock/mock_region_pack_data.dart';
import '../models/position_opinion.dart';
import '../models/sensor_status.dart';
import '../models/region_pack.dart';
import '../models/trust_scenario.dart';
import '../models/trust_event.dart';

/// Central mock repository — replace each method with real sensor/API calls.
class WhamiMockRepository {
  // ── Scenario state ─────────────────────────────────────────────────────────
  int _scenarioIndex = 0;

  List<TrustScenario> get scenarios => MockPositionData.scenarios;
  TrustScenario get activeScenario => scenarios[_scenarioIndex];

  void setScenario(int index) {
    if (index >= 0 && index < scenarios.length) {
      _scenarioIndex = index;
    }
  }

  // ── Positions ──────────────────────────────────────────────────────────────

  /// TODO: Replace with real sensor fusion output
  List<PositionOpinion> getPositionOpinions() => activeScenario.opinions;

  /// TODO: Replace with real fusion engine trust output
  PositionOpinion getTrustedPosition() =>
      activeScenario.opinions.firstWhere((o) => o.sourceType == 'whami');

  int getTrustScore() => activeScenario.trustScore;
  String getAlertMessage() => activeScenario.alertMessage;

  // ── Sensors ────────────────────────────────────────────────────────────────

  /// TODO: Replace with real SensorManager bindings
  List<SensorStatus> getSensorStatuses() => activeScenario.sensors;

  // ── Region packs ───────────────────────────────────────────────────────────

  final List<RegionPack> _packs = List.from(MockRegionPackData.packs);

  /// TODO: Replace with local file system pack manager
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
    }
  }

  // ── Trust events ───────────────────────────────────────────────────────────

  /// TODO: Replace with persisted trust event log
  List<TrustEvent> getTrustEvents() => MockAlertData.events;

  // ── Trust breakdown ────────────────────────────────────────────────────────

  /// Mock trust formula: 0.45×Landmark + 0.20×GPS + 0.15×Magnetic + 0.10×IMU + 0.10×Sky
  Map<String, dynamic> getTrustBreakdown() {
    final opinions = activeScenario.opinions;

    int landmarkConf = _confidenceFor(opinions, 'landmark');
    int gpsConf = _confidenceFor(opinions, 'gps');
    int magConf = _confidenceFor(opinions, 'magnetic');
    int imuConf = _confidenceFor(opinions, 'imu');
    int skyConf = _confidenceFor(opinions, 'sextant');

    final score = (0.45 * landmarkConf +
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

  // ── Default sensors (for normal scenario reference) ────────────────────────
  List<SensorStatus> get defaultSensors => MockSensorData.normalSensors;
}
