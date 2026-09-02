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
      };
}
