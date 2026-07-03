import 'dart:convert';

class RegionVersions {
  final String engine;
  final String schema;
  final String data;
  final String map;
  final String landmarks;
  final String magnetic;

  const RegionVersions({
    required this.engine,
    required this.schema,
    required this.data,
    required this.map,
    required this.landmarks,
    required this.magnetic,
  });

  factory RegionVersions.fromJson(Map<String, dynamic> json) {
    return RegionVersions(
      engine: json['engine'] as String? ?? '2.0.0',
      schema: json['schema'] as String? ?? '1.0.0',
      data: json['data'] as String? ?? '',
      map: json['map'] as String? ?? '1.0.0',
      landmarks: json['landmarks'] as String? ?? '1.0.0',
      magnetic: json['magnetic'] as String? ?? '1.0.0',
    );
  }

  Map<String, String> toJson() {
    return {
      'engine': engine,
      'schema': schema,
      'data': data,
      'map': map,
      'landmarks': landmarks,
      'magnetic': magnetic,
    };
  }
}

class RegionMetadata {
  final String id;
  final String name;
  final String country;
  final RegionVersions versions;
  final List<double> bounds; // [minLat, minLng, maxLat, maxLng]
  final String checksum;
  final int sizeBytes;
  final String packType;
  final int trustScore;

  const RegionMetadata({
    required this.id,
    required this.name,
    required this.country,
    required this.versions,
    required this.bounds,
    required this.checksum,
    required this.sizeBytes,
    required this.packType,
    required this.trustScore,
  });

  factory RegionMetadata.fromJson(Map<String, dynamic> json) {
    final boundsRaw = json['bounds'] as List<dynamic>? ?? [0.0, 0.0, 0.0, 0.0];
    final boundsList = boundsRaw.map((e) => (e as num).toDouble()).toList();

    return RegionMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      country: json['country'] as String? ?? '',
      versions: RegionVersions.fromJson(json['versions'] as Map<String, dynamic>? ?? {}),
      bounds: boundsList,
      checksum: json['checksum'] as String? ?? '',
      sizeBytes: json['size'] as int? ?? 0,
      packType: json['packType'] as String? ?? json['type'] as String? ?? 'Unknown',
      trustScore: json['trustScore'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'country': country,
      'versions': versions.toJson(),
      'bounds': bounds,
      'checksum': checksum,
      'size': sizeBytes,
      'packType': packType,
      'trustScore': trustScore,
    };
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
