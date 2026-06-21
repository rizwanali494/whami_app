class SensorStatus {
  final String id;
  final String name;
  final String status; // active, available, unavailable, unstable
  final int confidence;
  final String latestValue;
  final String healthMessage;
  final String iconName;
  final DateTime lastUpdated;

  SensorStatus({
    required this.id,
    required this.name,
    required this.status,
    required this.confidence,
    required this.latestValue,
    required this.healthMessage,
    required this.iconName,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  SensorStatus copyWith({
    String? status,
    int? confidence,
    String? latestValue,
    String? healthMessage,
    DateTime? lastUpdated,
  }) {
    return SensorStatus(
      id: id,
      name: name,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      latestValue: latestValue ?? this.latestValue,
      healthMessage: healthMessage ?? this.healthMessage,
      iconName: iconName,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  /// GPS sensor status from live reading
  factory SensorStatus.gps({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'gps',
      name: 'GPS / GNSS',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'satellite_alt',
    );
  }

  /// Magnetometer status from live reading
  factory SensorStatus.magnetometer({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'magnetometer',
      name: 'Magnetometer',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'explore',
    );
  }

  /// IMU status from live reading
  factory SensorStatus.imu({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'imu',
      name: 'IMU',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'directions_walk',
    );
  }

  /// Gyroscope status from live reading
  factory SensorStatus.gyroscope({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'gyroscope',
      name: 'Gyroscope',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'rotate_90_degrees_ccw',
    );
  }

  /// Barometer status from live reading
  factory SensorStatus.barometer({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'barometer',
      name: 'Barometer',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'compress',
    );
  }

  /// Sky / Celestial status
  factory SensorStatus.sky({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'sky',
      name: 'Sky / Celestial',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'wb_sunny',
    );
  }

  /// Fusion engine status
  factory SensorStatus.fusion({
    required String status,
    required int confidence,
    required String value,
    required String health,
  }) {
    return SensorStatus(
      id: 'fusion',
      name: 'TrustFusionEngine',
      status: status,
      confidence: confidence,
      latestValue: value,
      healthMessage: health,
      iconName: 'hub',
    );
  }

  /// Unavailable sensor
  factory SensorStatus.unavailable({
    required String id,
    required String name,
    required String iconName,
  }) {
    return SensorStatus(
      id: id,
      name: name,
      status: 'unavailable',
      confidence: 0,
      latestValue: 'Unavailable',
      healthMessage: 'Sensor not available on this device',
      iconName: iconName,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
