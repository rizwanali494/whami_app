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

  // Remote source for packs that aren't downloaded yet (from catalog.json)
  final String? downloadUrl;
  final String? checksum;

  /// One-tap mission profile: aviation | border | disaster | marine | none
  final String missionProfile;

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
    this.downloadUrl,
    this.checksum,
    this.missionProfile = 'none',
  });

  bool get isMissionPack =>
      missionProfile != 'none' && missionProfile.isNotEmpty;

  RegionPack copyWith({
    String? status,
    double? downloadProgress,
    String? downloadStage,
    bool? isDownloading,
    String? localPath,
    RegionMetadata? metadata,
    String? downloadUrl,
    String? checksum,
    String? missionProfile,
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
      downloadUrl: downloadUrl ?? this.downloadUrl,
      checksum: checksum ?? this.checksum,
      missionProfile: missionProfile ?? this.missionProfile,
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
    // Format bytes to readable size (tiny demo stubs show as Demo, not 0.0 MB).
    final sizeStr = _formatPackSize(meta.sizeBytes);

    final stubMap = meta.versions.map.toLowerCase().contains('stub') ||
        meta.checksum == 'bundled-demo' ||
        sizeStr == 'Demo';
    return RegionPack(
      id: meta.id,
      name: meta.name,
      type: meta.packType,
      size: sizeStr,
      status: status,
      location: meta.description ?? meta.country,
      lastUpdated: meta.createdAt ?? meta.versions.data,
      includedData: stubMap
          ? const ['Landmarks', 'Demo coverage']
          : const ['Land maps', 'SQLite database', 'MBTiles maps'],
      trustScore: meta.trustScore,
      localPath: diskPath,
      metadata: meta,
      checksum: meta.checksum,
    );
  }

  static String _formatPackSize(int sizeBytes) {
    if (sizeBytes <= 0) return 'Demo';
    final mb = sizeBytes / (1024 * 1024);
    if (mb < 0.1) return 'Demo';
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Create a not-yet-downloaded RegionPack from a catalog.json entry
  factory RegionPack.fromCatalogEntry(Map<String, dynamic> json) {
    final sizeBytes = json['sizeBytes'] as int? ?? 0;
    final sizeStr = json['bundled'] == true
        ? 'Demo'
        : _formatPackSize(sizeBytes);

    final bundled = json['bundled'] == true;
    final packType = json['packType'] as String? ?? 'Unknown';
    final mission = (json['missionProfile'] as String?) ??
        _inferMissionProfile(packType);
    return RegionPack(
      id: json['id'] as String,
      name: json['name'] as String,
      type: packType,
      size: sizeStr,
      status: 'available',
      location: json['country'] as String? ?? '',
      lastUpdated: '',
      includedData: bundled
          ? const ['Landmarks', 'Demo coverage']
          : const ['Land maps', 'SQLite database', 'MBTiles maps'],
      trustScore: json['trustScore'] as int? ?? 0,
      localPath: null,
      metadata: null,
      downloadUrl: json['downloadUrl'] as String?,
      checksum: json['checksum'] as String?,
      missionProfile: mission,
    );
  }

  static String _inferMissionProfile(String packType) {
    switch (packType.toLowerCase()) {
      case 'aviation':
        return 'aviation';
      case 'marine':
        return 'marine';
      case 'hiking':
      case 'desert':
      case 'arctic':
        return 'disaster';
      case 'urban':
        return 'border';
      default:
        return 'none';
    }
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

  /// Bundled / stub packs without real offline vector tiles.
  bool get isDemoPack {
    if (size == 'Demo') return true;
    if (checksum == 'bundled-demo') return true;
    final mapVer = metadata?.versions.map;
    if (mapVer != null && mapVer.toLowerCase().contains('stub')) return true;
    return false;
  }

  /// True when this pack is expected to include offline map tiles (not demo).
  bool get hasOfflineMapTiles => !isDemoPack;

  String get coverageSummary {
    if (isDemoPack) {
      return 'Landmarks for Tocumwal / Riverina · streets use online/cached basemap';
    }
    return includedData.isEmpty
        ? 'Offline maps + landmarks'
        : includedData.join(' · ');
  }
}
