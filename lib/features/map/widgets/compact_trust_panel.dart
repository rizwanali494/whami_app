import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../core/trust/trust_summary.dart';
import '../../../data/models/position_opinion.dart';

/// Floating aviation trust card — collapsed by default (~70% map remains visible).
class CompactTrustPanel extends StatelessWidget {
  final TrustSummary summary;
  final List<PositionOpinion> opinions;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenVerify;

  const CompactTrustPanel({
    super.key,
    required this.summary,
    required this.opinions,
    required this.expanded,
    required this.onToggle,
    required this.onOpenVerify,
  });

  @override
  Widget build(BuildContext context) {
    final color = summary.level.color;
    final active = opinions.where((o) => o.status != 'unavailable').toList();
    final tablet = WhamiLayout.isTablet(context);

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(
          maxWidth: tablet ? 420 : 360,
          maxHeight: expanded ? (tablet ? 420 : 340) : 72,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF0122033), Color(0xF00A1628)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accent edge
              Container(height: 2.5, color: color),
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(
                          summary.level == TrustLevel.reliable
                              ? Icons.check_rounded
                              : summary.level.icon,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${summary.headline.toUpperCase()}  ·  ${summary.score}/100',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              summary.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            summary.explanation,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'VERIFICATION SOURCES',
                          style: WhamiAviation.overline(
                            color: WhamiAviation.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (active.isEmpty)
                          Text(
                            'Start tracking to collect sensors.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          )
                        else
                          ...active.map((op) => _SourceLine(opinion: op)),
                        if (summary.level == TrustLevel.caution ||
                            summary.level == TrustLevel.unreliable) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 42,
                            child: FilledButton(
                              onPressed: onOpenVerify,
                              style: FilledButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Verify Position',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  final PositionOpinion opinion;
  const _SourceLine({required this.opinion});

  @override
  Widget build(BuildContext context) {
    final unstable = opinion.status == 'unstable';
    final verifyOnly = opinion.status == 'verify';
    final scoreColor = unstable || verifyOnly
        ? AppColors.trustMediumDark
        : AppColors.forTrust(opinion.confidence);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              opinion.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '${opinion.confidence}%',
            style: TextStyle(
              color: scoreColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
