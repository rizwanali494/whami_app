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
  });

  RegionPack copyWith({
    String? status,
    double? downloadProgress,
    String? downloadStage,
    bool? isDownloading,
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
    );
  }
}
