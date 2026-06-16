class SensorStatus {
  final String id;
  final String name;
  final String status; // active, available, unavailable, unstable
  final int confidence;
  final String latestValue;
  final String healthMessage;
  final String iconName;

  const SensorStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.confidence,
    required this.latestValue,
    required this.healthMessage,
    required this.iconName,
  });

  SensorStatus copyWith({
    String? status,
    int? confidence,
    String? latestValue,
    String? healthMessage,
  }) {
    return SensorStatus(
      id: id,
      name: name,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      latestValue: latestValue ?? this.latestValue,
      healthMessage: healthMessage ?? this.healthMessage,
      iconName: iconName,
    );
  }
}
