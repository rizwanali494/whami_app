class TrustEvent {
  final String id;
  final String title;
  final String severity; // info, warning, critical
  final String time;
  final String description;
  final String iconName;

  const TrustEvent({
    required this.id,
    required this.title,
    required this.severity,
    required this.time,
    required this.description,
    required this.iconName,
  });
}
