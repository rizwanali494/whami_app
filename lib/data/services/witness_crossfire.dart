import 'dart:math';

import '../models/position_opinion.dart';

/// One witness in the Crossfire jury.
class CrossfireWitness {
  final String id;
  final String name;
  final String shortCode;
  final String sourceType;
  final double latitude;
  final double longitude;
  final int confidence;
  final String status;
  final bool agrees;
  final bool isOutlier;
  final double distanceFromTrustedM;
  final String why;

  const CrossfireWitness({
    required this.id,
    required this.name,
    required this.shortCode,
    required this.sourceType,
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.status,
    required this.agrees,
    required this.isOutlier,
    required this.distanceFromTrustedM,
    required this.why,
  });
}

/// Plain-language jury of witnesses vs the trusted fix.
class WitnessCrossfire {
  final bool visible;
  final String headline;
  final double trustedLat;
  final double trustedLng;
  final List<CrossfireWitness> witnesses;
  final List<String> agreeingIds;
  final List<String> outlierIds;

  const WitnessCrossfire({
    required this.visible,
    required this.headline,
    required this.trustedLat,
    required this.trustedLng,
    required this.witnesses,
    required this.agreeingIds,
    required this.outlierIds,
  });

  static const empty = WitnessCrossfire(
    visible: false,
    headline: '',
    trustedLat: 0,
    trustedLng: 0,
    witnesses: [],
    agreeingIds: [],
    outlierIds: [],
  );

  /// Build jury from fusion opinions around the trusted pin.
  static WitnessCrossfire fromOpinions({
    required List<PositionOpinion> opinions,
    required double trustedLat,
    required double trustedLng,
    required int trustScore,
    required bool gnssSuspicious,
    required bool isTracking,
    double agreeRadiusM = 120,
    double outlierRadiusM = 250,
  }) {
    if (!isTracking) return empty;

    final candidates = opinions.where((o) {
      if (o.status == 'unavailable') return false;
      if (o.sourceType == 'whami') return false;
      if (o.latitude == 0 && o.longitude == 0) return false;
      // Baro / mag without independent lat still pin to GPS — keep if unstable or far.
      return true;
    }).toList();

    if (candidates.length < 2) return empty;

    final levelBad = trustScore < 75 || gnssSuspicious;
    if (!levelBad) {
      // Still show a soft crossfire when GPS is flagged even at high score.
      return empty;
    }

    final witnesses = <CrossfireWitness>[];
    final agreeing = <String>[];
    final outliers = <String>[];

    for (final o in candidates) {
      final dist = _haversine(
        trustedLat,
        trustedLng,
        o.latitude,
        o.longitude,
      );
      final weak = o.status == 'unstable' || o.confidence < 55;
      final far = dist > outlierRadiusM;
      final near = dist <= agreeRadiusM && !weak;
      final isOutlier = weak || far || (o.sourceType == 'gps' && gnssSuspicious);
      final agrees = near && !isOutlier;

      if (agrees) {
        agreeing.add(o.id);
      } else if (isOutlier) {
        outliers.add(o.id);
      }

      witnesses.add(
        CrossfireWitness(
          id: o.id,
          name: o.name,
          shortCode: o.shortCode,
          sourceType: o.sourceType,
          latitude: o.latitude,
          longitude: o.longitude,
          confidence: o.confidence,
          status: o.status,
          agrees: agrees,
          isOutlier: isOutlier,
          distanceFromTrustedM: dist,
          why: _why(o, dist, gnssSuspicious, weak, far),
        ),
      );
    }

    // Prefer naming GPS when it is the clear outlier.
    String headline;
    final gpsOut = witnesses.any((w) => w.sourceType == 'gps' && w.isOutlier);
    if (agreeing.isNotEmpty && gpsOut && outliers.length == 1) {
      headline =
          '${agreeing.length} sensor${agreeing.length == 1 ? '' : 's'} agree. GPS is the outlier.';
    } else if (agreeing.isNotEmpty && outliers.isNotEmpty) {
      final names = witnesses
          .where((w) => w.isOutlier)
          .map((w) => w.shortCode)
          .take(3)
          .join(' · ');
      headline =
          '${agreeing.length} agree. Outlier${outliers.length == 1 ? '' : 's'}: $names.';
    } else if (outliers.isNotEmpty) {
      headline =
          'Sensors disagree — ${outliers.length} weak or far from reality.';
    } else {
      headline =
          '${agreeing.length} of ${witnesses.length} sensors still aligned.';
    }

    return WitnessCrossfire(
      visible: true,
      headline: headline,
      trustedLat: trustedLat,
      trustedLng: trustedLng,
      witnesses: witnesses,
      agreeingIds: agreeing,
      outlierIds: outliers,
    );
  }

  static String _why(
    PositionOpinion o,
    double dist,
    bool gnssSuspicious,
    bool weak,
    bool far,
  ) {
    if (o.description.trim().isNotEmpty) return o.description;
    if (o.sourceType == 'gps' && gnssSuspicious) {
      return 'GPS claim diverges from real-world sensors.';
    }
    if (weak) return 'Signal unstable or low confidence (${o.confidence}%).';
    if (far) {
      final label = dist >= 1000
          ? '${(dist / 1000).toStringAsFixed(1)} km'
          : '${dist.round()} m';
      return 'Claims a fix $label from trusted reality.';
    }
    return 'Aligned with trusted reality (±${dist.round()} m).';
  }

  static double _haversine(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
