class Landmark {
  final String name;
  final double latitude;
  final double longitude;
  final double confidence;
  final bool saved;

  /// Visual category per architecture spec:
  /// bridge, tower, mountain, coastline, harbor, building, island, other
  final String type;

  const Landmark({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.saved,
    this.type = 'other',
  });
}
