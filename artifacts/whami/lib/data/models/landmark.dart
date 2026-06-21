class Landmark {
  final String name;
  final double latitude;
  final double longitude;
  final double confidence;
  final bool saved;

  const Landmark({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.saved,
  });
}
