import 'dart:convert';
import 'region_metadata.dart';

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

  // Rich metadata engine backing (optional, populated when downloaded/read)
  final RegionMetadata? metadata;

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
    this.metadata,
  });

  RegionPack copyWith({
    String? status,
    double? downloadProgress,
    String? downloadStage,
    bool? isDownloading,
    String? localPath,
    RegionMetadata? metadata,
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
      metadata: metadata ?? this.metadata,
    );
  }

  /// Create a RegionPack from a manifest.json stored on disk
  factory RegionPack.fromManifest(Map<String, dynamic> json, String diskPath) {
    RegionMetadata? meta;
    try {
      meta = RegionMetadata.fromJson(json);
    } catch (_) {
      // Allow fallback if metadata.json format is incomplete
    }

    return RegionPack(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? json['packType'] as String? ?? 'Unknown',
      size: json['size'] as String? ?? '0 MB',
      status: 'downloaded',
      location: json['location'] as String? ?? json['country'] as String? ?? '',
      lastUpdated: json['lastUpdated'] as String? ?? json['created'] as String? ?? '',
      includedData: (json['includedData'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      trustScore: json['trustScore'] as int? ?? 0,
      fileSizes: (json['fileSizes'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      localPath: diskPath,
      metadata: meta,
    );
  }

  /// Create from pure RegionMetadata
  factory RegionPack.fromMetadata(RegionMetadata meta, String diskPath, {String status = 'downloaded'}) {
    // Format bytes to readable size
    final double mb = meta.sizeBytes / (1024 * 1024);
    final sizeStr = '${mb.toStringAsFixed(1)} MB';

    return RegionPack(
      id: meta.id,
      name: meta.name,
      type: meta.packType,
      size: sizeStr,
      status: status,
      location: meta.country,
      lastUpdated: meta.versions.data,
      includedData: const ['Land maps', 'SQLite database', 'MBTiles maps'],
      trustScore: meta.trustScore,
      localPath: diskPath,
      metadata: meta,
    );
  }

  /// Serialize to JSON for saving as manifest.json
  Map<String, dynamic> toManifest() {
    if (metadata != null) {
      return metadata!.toJson();
    }
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
