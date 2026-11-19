import '../../core/trust/trust_summary.dart';
import '../models/position_opinion.dart';

/// Short operational advisory — aviation-style, never invents a position.
class TrustAdvisory {
  final String code;
  final String title;
  final String detail;
  final String severity; // info | caution | critical
  final String? actionLabel;
  final String? actionRoute;

  const TrustAdvisory({
    required this.code,
    required this.title,
    required this.detail,
    required this.severity,
    this.actionLabel,
    this.actionRoute,
  });
}

class TrustCopilot {
  TrustAdvisory? advise({
    required TrustSummary summary,
    required List<PositionOpinion> opinions,
    required bool isTracking,
    required bool gpsEnabled,
    required bool hasGpsFix,
    required bool gnssSuspicious,
    required bool hasLock,
    required bool hasActivePack,
    double? lieDistanceM,
  }) {
    if (!isTracking) {
      return const TrustAdvisory(
        code: 'STANDBY',
        title: 'Start tracking',
        detail: 'No live witnesses yet. Start tracking to verify position.',
        severity: 'info',
        actionLabel: null,
      );
    }

    if (gnssSuspicious) {
      final lie = lieDistanceM == null
          ? 'GPS claim diverged'
          : lieDistanceM >= 1000
              ? 'Lie line ${(lieDistanceM / 1000).toStringAsFixed(1)} km'
              : 'Lie line ${lieDistanceM.round()} m';
      return TrustAdvisory(
        code: 'SPOOF',
        title: 'Hold trusted fix',
        detail: '$lie. Prefer lock / pack geometry — do not follow raw GPS.',
        severity: 'critical',
        actionLabel: 'Verify',
        actionRoute: '/verify',
      );
    }

    if (!gpsEnabled) {
      return TrustAdvisory(
        code: 'SENSORS',
        title: 'Sensors only',
        detail: hasLock
            ? 'GPS paused. Real-world lock is anchoring trust.'
            : 'GPS paused. Enable GPS or lock a landmark.',
        severity: hasLock ? 'info' : 'caution',
        actionLabel: hasLock ? null : 'Verify',
        actionRoute: hasLock ? null : '/verify',
      );
    }

    if (!hasGpsFix) {
      return TrustAdvisory(
        code: 'NOFIX',
        title: 'Waiting for GNSS',
        detail: hasLock
            ? 'No GPS fix yet — lock is carrying position trust.'
            : 'Seek open sky, or verify a nearby landmark.',
        severity: hasLock ? 'info' : 'caution',
        actionLabel: hasLock ? null : 'Verify',
        actionRoute: hasLock ? null : '/verify',
      );
    }

    if (summary.level == TrustLevel.unreliable) {
      return TrustAdvisory(
        code: 'UNREL',
        title: 'Position unreliable',
        detail: hasActivePack
            ? 'Sources conflict. Cross-check with Verify or pack landmarks.'
            : 'Sources conflict. Download an offline pack for this area.',
        severity: 'critical',
        actionLabel: hasActivePack ? 'Verify' : 'Offline',
        actionRoute: hasActivePack ? '/verify' : '/offline',
      );
    }

    if (summary.level == TrustLevel.caution) {
      return const TrustAdvisory(
        code: 'CAUTION',
        title: 'Verify when practical',
        detail: 'Partial disagreement. Prefer open sky or lock a landmark.',
        severity: 'caution',
        actionLabel: 'Verify',
        actionRoute: '/verify',
      );
    }

    final active = opinions.where((o) => o.status != 'unavailable').length;
    return TrustAdvisory(
      code: 'OK',
      title: 'Position reliable',
      detail:
          '$active witnesses online · score ${summary.score}/100. Continue.',
      severity: 'info',
    );
  }
}
