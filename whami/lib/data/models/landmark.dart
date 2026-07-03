enum LandmarkSource {
  system,
  user,
  ar,
}

class Landmark {
  final String id;
  final String name;
  final String category;     // bridge, tower, mountain, coastline, harbor, building, island, other
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? description;
  final bool verified;
  final double confidence;
  final String? imagePath;
  final LandmarkSource source;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Compatibility fields/getters
  bool get saved => source != LandmarkSource.system;
  String get type => category;

  const Landmark({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.description,
    required this.verified,
    required this.confidence,
    this.imagePath,
    required this.source,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Compatibility constructor for existing manual instantiations
  factory Landmark.legacy({
    required String name,
    required double latitude,
    required double longitude,
    required double confidence,
    required bool saved,
    String type = 'other',
  }) {
    final now = DateTime.now();
    return Landmark(
      id: '${latitude}_${longitude}_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      category: type,
      latitude: latitude,
      longitude: longitude,
      verified: saved,
      confidence: confidence,
      source: saved ? LandmarkSource.user : LandmarkSource.system,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create a Landmark from a SQL Row map
  factory Landmark.fromSqlRow(Map<String, dynamic> row) {
    LandmarkSource parsedSource = LandmarkSource.system;
    final sourceStr = row['source'] as String? ?? 'SYSTEM';
    if (sourceStr == 'USER') {
      parsedSource = LandmarkSource.user;
    } else if (sourceStr == 'AR') {
      parsedSource = LandmarkSource.ar;
    }

    return Landmark(
      id: row['id'] as String,
      name: row['name'] as String? ?? 'Unnamed',
      category: row['category'] as String? ?? 'other',
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      altitude: row['altitude'] != null ? (row['altitude'] as num).toDouble() : null,
      description: row['description'] as String?,
      verified: (row['verified'] as int? ?? 0) == 1,
      confidence: (row['confidence'] as num? ?? 1.0).toDouble(),
      imagePath: row['imagePath'] as String?,
      source: parsedSource,
      isFavorite: (row['isFavorite'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updatedAt'] as int? ?? 0),
    );
  }

  /// Convert a Landmark to a SQL Row map
  Map<String, dynamic> toSqlRow() {
    String sourceStr = 'SYSTEM';
    if (source == LandmarkSource.user) {
      sourceStr = 'USER';
    } else if (source == LandmarkSource.ar) {
      sourceStr = 'AR';
    }

    return {
      'id': id,
      'name': name,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'description': description,
      'verified': verified ? 1 : 0,
      'confidence': confidence,
      'imagePath': imagePath,
      'source': sourceStr,
      'isFavorite': isFavorite ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  Landmark copyWith({
    String? id,
    String? name,
    String? category,
    double? latitude,
    double? longitude,
    double? altitude,
    String? description,
    bool? verified,
    double? confidence,
    String? imagePath,
    LandmarkSource? source,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Landmark(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      description: description ?? this.description,
      verified: verified ?? this.verified,
      confidence: confidence ?? this.confidence,
      imagePath: imagePath ?? this.imagePath,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
