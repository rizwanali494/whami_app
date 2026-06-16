class RegionPack {
  final String id;
  final String name;
  final String type; // Marine, Lake, Hiking, Urban
  final String size;
  final String status; // downloaded, available, update_needed
  final String location;
  final String lastUpdated;
  final List<String> includedData;
  final int trustScore;

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
  });

  RegionPack copyWith({String? status}) {
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
    );
  }
}
