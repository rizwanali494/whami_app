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
  });

  bool get isActive => status == 'active';

  PositionOpinion copyWith({
    double? latitude,
    double? longitude,
    int? confidence,
    double? uncertaintyRadius,
    String? status,
    String? description,
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
    );
  }
}
