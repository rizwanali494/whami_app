import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../data/models/position_opinion.dart';

/// Plain-language trust bands for the primary UI.
enum TrustLevel {
  reliable,
  caution,
  unreliable,
  unknown,
}

extension TrustLevelX on TrustLevel {
  String get label {
    switch (this) {
      case TrustLevel.reliable:
        return 'Position reliable';
      case TrustLevel.caution:
        return 'Verify position';
      case TrustLevel.unreliable:
        return 'Position unreliable';
      case TrustLevel.unknown:
        return 'Checking position';
    }
  }

  String get shortLabel {
    switch (this) {
      case TrustLevel.reliable:
        return 'Reliable';
      case TrustLevel.caution:
        return 'Verify';
      case TrustLevel.unreliable:
        return 'Unreliable';
      case TrustLevel.unknown:
        return 'Checking';
    }
  }

  IconData get icon {
    switch (this) {
      case TrustLevel.reliable:
        return Icons.verified_user;
      case TrustLevel.caution:
        return Icons.warning_amber_rounded;
      case TrustLevel.unreliable:
        return Icons.gpp_bad;
      case TrustLevel.unknown:
        return Icons.hourglass_top;
    }
  }

  Color get color {
    switch (this) {
      case TrustLevel.reliable:
        return AppColors.trustHigh;
      case TrustLevel.caution:
        return AppColors.trustMediumDark;
      case TrustLevel.unreliable:
        return AppColors.trustLow;
      case TrustLevel.unknown:
        return AppColors.textSecondary;
    }
  }

  String explanation(int score) {
    switch (this) {
      case TrustLevel.reliable:
        return 'Score $score means most witnesses agree. You can navigate with this fix.';
      case TrustLevel.caution:
        return 'Score $score means sources partially disagree. Prefer open sky or verify a landmark.';
      case TrustLevel.unreliable:
        return 'Score $score means sources conflict or are missing. Do not rely on this position alone.';
      case TrustLevel.unknown:
        return 'WHAMI is still gathering sensor and offline witnesses.';
    }
  }

  String get suggestedAction {
    switch (this) {
      case TrustLevel.reliable:
        return 'Keep tracking. Optionally scan a landmark to lock confidence higher.';
      case TrustLevel.caution:
        return 'Move to an open area, or open Verify to scan a nearby landmark.';
      case TrustLevel.unreliable:
        return 'Stop and cross-check with Verify, or download an offline pack for this area.';
      case TrustLevel.unknown:
        return 'Start tracking and wait for a GPS fix.';
    }
  }
}

class TrustSummary {
  final TrustLevel level;
  final int score;
  final int agreeingSources;
  final int totalSources;
  final double uncertaintyMeters;
  final String headline;
  final String subtitle;
  final String explanation;
  final String action;

  const TrustSummary({
    required this.level,
    required this.score,
    required this.agreeingSources,
    required this.totalSources,
    required this.uncertaintyMeters,
    required this.headline,
    required this.subtitle,
    required this.explanation,
    required this.action,
  });

  static TrustSummary fromOpinions({
    required int trustScore,
    required List<PositionOpinion> opinions,
    required bool isTracking,
  }) {
    if (!isTracking && opinions.every((o) => o.status == 'unavailable')) {
      return TrustSummary(
        level: TrustLevel.unknown,
        score: trustScore,
        agreeingSources: 0,
        totalSources: opinions.isEmpty ? 5 : opinions.length,
        uncertaintyMeters: 0,
        headline: TrustLevel.unknown.label,
        subtitle: 'Start tracking to verify your position',
        explanation: TrustLevel.unknown.explanation(trustScore),
        action: TrustLevel.unknown.suggestedAction,
      );
    }

    final active = opinions.where((o) => o.status != 'unavailable').toList();
    final total = opinions.isEmpty ? 5 : opinions.length;
    final agreeing = active.where((o) {
      if (o.status == 'unstable') return false;
      return o.confidence >= 55;
    }).length;

    final uncertainty = active.isEmpty
        ? 0.0
        : active
            .map((o) => o.uncertaintyRadius)
            .reduce((a, b) => a < b ? a : b);

    final level = trustScore >= 75
        ? TrustLevel.reliable
        : trustScore >= 55
            ? TrustLevel.caution
            : TrustLevel.unreliable;

    final radiusLabel = uncertainty <= 0
        ? 'acquiring fix'
        : uncertainty >= 1000
            ? '±${(uncertainty / 1000).toStringAsFixed(1)} km'
            : '±${uncertainty.round()} m';

    return TrustSummary(
      level: level,
      score: trustScore,
      agreeingSources: agreeing,
      totalSources: total,
      uncertaintyMeters: uncertainty,
      headline: level.label,
      subtitle: '$agreeing of $total sources agree · $radiusLabel',
      explanation: level.explanation(trustScore),
      action: level.suggestedAction,
    );
  }
}
