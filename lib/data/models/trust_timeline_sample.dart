/// One sample in the trust timeline (recorded while tracking).
class TrustTimelineSample {
  final DateTime timestamp;
  final int trustScore;
  final String level; // reliable | caution | unreliable | unknown
  final double latitude;
  final double longitude;
  final double uncertaintyM;
  final bool gnssSuspicious;
  final String? alertMessage;
  final Map<String, int> witnessScores;
  final List<String> brokenWitnesses;

  /// Ghost pin (GPS claim) when suspicious.
  final double? gpsClaimLatitude;
  final double? gpsClaimLongitude;

  /// Trusted pin for that sample (lock / fuse).
  final double? trustedLatitude;
  final double? trustedLongitude;
  final double? lieDistanceM;

  const TrustTimelineSample({
    required this.timestamp,
    required this.trustScore,
    required this.level,
    required this.latitude,
    required this.longitude,
    required this.uncertaintyM,
    required this.gnssSuspicious,
    required this.witnessScores,
    required this.brokenWitnesses,
    this.alertMessage,
    this.gpsClaimLatitude,
    this.gpsClaimLongitude,
    this.trustedLatitude,
    this.trustedLongitude,
    this.lieDistanceM,
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'trustScore': trustScore,
        'level': level,
        'lat': latitude,
        'lng': longitude,
        'uncertaintyM': uncertaintyM,
        'gnssSuspicious': gnssSuspicious,
        'alertMessage': alertMessage,
        'witnessScores': witnessScores,
        'brokenWitnesses': brokenWitnesses,
        if (gpsClaimLatitude != null) 'gpsClaimLat': gpsClaimLatitude,
        if (gpsClaimLongitude != null) 'gpsClaimLng': gpsClaimLongitude,
        if (trustedLatitude != null) 'trustedLat': trustedLatitude,
        if (trustedLongitude != null) 'trustedLng': trustedLongitude,
        if (lieDistanceM != null) 'lieDistanceM': lieDistanceM,
      };
}
