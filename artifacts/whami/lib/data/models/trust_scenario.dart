import 'position_opinion.dart';
import 'sensor_status.dart';

class TrustScenario {
  final String id;
  final String name;
  final int trustScore;
  final String alertMessage;
  final List<PositionOpinion> opinions;
  final List<SensorStatus> sensors;

  const TrustScenario({
    required this.id,
    required this.name,
    required this.trustScore,
    required this.alertMessage,
    required this.opinions,
    required this.sensors,
  });
}
