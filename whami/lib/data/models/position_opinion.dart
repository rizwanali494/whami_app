class PositionOpinion {
  final String id;
  final String name;
  final String shortCode;
  final String sourceType;
  final double latitude;
  final double longitude;
  final int confidence;
  final double uncertaintyRadius; // in meters
  final String colorName;
  final String status; // active, unavailable, unstable
  final String description;
  final DateTime timestamp;

  const PositionOpinion({
    required this.id,
    required this.name,
    required this.shortCode,
    required this.sourceType,
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.uncertaintyRadius,
    required this.colorName,
    required this.status,
    required this.description,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? const _EpochDateTime();

  bool get isActive => status == 'active';

  PositionOpinion copyWith({
    double? latitude,
    double? longitude,
    int? confidence,
    double? uncertaintyRadius,
    String? status,
    String? description,
    DateTime? timestamp,
  }) {
    return PositionOpinion(
      id: id,
      name: name,
      shortCode: shortCode,
      sourceType: sourceType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      confidence: confidence ?? this.confidence,
      uncertaintyRadius: uncertaintyRadius ?? this.uncertaintyRadius,
      colorName: colorName,
      status: status ?? this.status,
      description: description ?? this.description,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Create a GPS opinion from a live reading
  factory PositionOpinion.fromGps({
    required double latitude,
    required double longitude,
    required double accuracy,
    required String status,
    String description = '',
  }) {
    final conf = _accuracyToConfidence(accuracy);
    return PositionOpinion(
      id: 'gps',
      name: 'GPS / GNSS',
      shortCode: 'G',
      sourceType: 'gps',
      latitude: latitude,
      longitude: longitude,
      confidence: conf,
      uncertaintyRadius: accuracy,
      colorName: 'blue',
      status: status,
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Create a landmark opinion from a match result
  factory PositionOpinion.fromLandmark({
    required double latitude,
    required double longitude,
    required int confidence,
    required double uncertaintyRadius,
    required String status,
    String description = '',
  }) {
    return PositionOpinion(
      id: 'landmark',
      name: 'Landmark / Seamap',
      shortCode: 'L',
      sourceType: 'landmark',
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      uncertaintyRadius: uncertaintyRadius,
      colorName: 'black',
      status: status,
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Create a magnetic field opinion
  factory PositionOpinion.fromMagnetic({
    required double latitude,
    required double longitude,
    required int confidence,
    required double uncertaintyRadius,
    required String status,
    String description = '',
  }) {
    return PositionOpinion(
      id: 'magnetic',
      name: 'Magnetic Field',
      shortCode: 'M',
      sourceType: 'magnetic',
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      uncertaintyRadius: uncertaintyRadius,
      colorName: 'red',
      status: status,
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Create an IMU opinion from dead-reckoning
  factory PositionOpinion.fromImu({
    required double latitude,
    required double longitude,
    required int confidence,
    required double uncertaintyRadius,
    required String status,
    String description = '',
  }) {
    return PositionOpinion(
      id: 'imu',
      name: 'IMU Movement',
      shortCode: 'I',
      sourceType: 'imu',
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      uncertaintyRadius: uncertaintyRadius,
      colorName: 'purple',
      status: status,
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Create a sky/celestial opinion
  factory PositionOpinion.fromSky({
    required double latitude,
    required double longitude,
    required int confidence,
    required double uncertaintyRadius,
    required String status,
    String description = '',
  }) {
    return PositionOpinion(
      id: 'sextant',
      name: 'Sextant / Sky',
      shortCode: 'S',
      sourceType: 'sextant',
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      uncertaintyRadius: uncertaintyRadius,
      colorName: 'green',
      status: status,
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Create the fused WHAMI position opinion
  factory PositionOpinion.whami({
    required double latitude,
    required double longitude,
    required int confidence,
    required double uncertaintyRadius,
    String description = '',
  }) {
    return PositionOpinion(
      id: 'whami',
      name: 'WHAMI Trusted Position',
      shortCode: 'W',
      sourceType: 'whami',
      latitude: latitude,
      longitude: longitude,
      confidence: confidence,
      uncertaintyRadius: uncertaintyRadius,
      colorName: 'amber',
      status: 'active',
      description: description,
      timestamp: DateTime.now(),
    );
  }

  /// Convert GPS accuracy (meters) to confidence (0-100)
  static int _accuracyToConfidence(double accuracy) {
    if (accuracy <= 5) return 95;
    if (accuracy <= 10) return 90;
    if (accuracy <= 20) return 82;
    if (accuracy <= 50) return 72;
    if (accuracy <= 100) return 55;
    if (accuracy <= 200) return 35;
    return 15;
  }

  /// An unavailable source
  factory PositionOpinion.unavailable({
    required String id,
    required String name,
    required String shortCode,
    required String sourceType,
    required String colorName,
    String description = 'Sensor unavailable',
  }) {
    return PositionOpinion(
      id: id,
      name: name,
      shortCode: shortCode,
      sourceType: sourceType,
      latitude: 0,
      longitude: 0,
      confidence: 0,
      uncertaintyRadius: 0,
      colorName: colorName,
      status: 'unavailable',
      description: description,
      timestamp: DateTime.now(),
    );
  }
}

/// Sentinel for const DateTime default
class _EpochDateTime implements DateTime {
  const _EpochDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      DateTime.fromMillisecondsSinceEpoch(0);
}
