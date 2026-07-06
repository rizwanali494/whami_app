import 'dart:convert';

class RegionPack {
  final String id;
  final String name;
  final String type; // Marine, Lake, Hiking, Urban
  final String size;
  final String status; // downloaded, available, update_needed, downloading
  final String location;
  final String lastUpdated;
  final List<String> includedData;
  final int trustScore;

  // Download tracking
  final double downloadProgress; // 0.0 – 1.0
  final String downloadStage; // e.g. "Downloading landmarks..."
  final bool isDownloading;

  // File manifest (type → size string)
  final Map<String, String> fileSizes;

  // Local filesystem path (null if not downloaded)
  final String? localPath;

  const RegionPack({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.status,
    required this.location,
    required this.lastUpdated,
    required this.includedData,
    required this.trustScore,
    this.downloadProgress = 0.0,
    this.downloadStage = '',
    this.isDownloading = false,
    this.fileSizes = const {},
    this.localPath,
  });

  RegionPack copyWith({
    String? status,
    double? downloadProgress,
    String? downloadStage,
    bool? isDownloading,
    String? localPath,
  }) {
    return RegionPack(
      id: id,
      name: name,
      type: type,
      size: size,
      status: status ?? this.status,
      location: location,
      lastUpdated: lastUpdated,
      includedData: includedData,
      trustScore: trustScore,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadStage: downloadStage ?? this.downloadStage,
      isDownloading: isDownloading ?? this.isDownloading,
      fileSizes: fileSizes,
      localPath: localPath ?? this.localPath,
    );
  }

  /// Create a RegionPack from a manifest.json stored on disk
  factory RegionPack.fromManifest(Map<String, dynamic> json, String diskPath) {
    return RegionPack(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'Unknown',
      size: json['size'] as String? ?? '0 MB',
      status: 'downloaded',
      location: json['location'] as String? ?? '',
      lastUpdated: json['lastUpdated'] as String? ?? '',
      includedData: (json['includedData'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      trustScore: json['trustScore'] as int? ?? 0,
      fileSizes: (json['fileSizes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      localPath: diskPath,
    );
  }

  /// Serialize to JSON for saving as manifest.json
  Map<String, dynamic> toManifest() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size,
      'location': location,
      'lastUpdated': lastUpdated,
      'includedData': includedData,
      'trustScore': trustScore,
      'fileSizes': fileSizes,
    };
  }

  String toManifestJson() => const JsonEncoder.withIndent('  ').convert(toManifest());
}
