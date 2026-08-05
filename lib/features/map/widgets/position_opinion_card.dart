import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class PositionOpinionCard extends StatelessWidget {
  final PositionOpinion opinion;

  const PositionOpinionCard({super.key, required this.opinion});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forSource(opinion.sourceType);
    final isUnavailable = opinion.status == 'unavailable';
    final isUnstable = opinion.status == 'unstable';

    return Semantics(
      label:
          '${opinion.name}: ${isUnavailable ? "unavailable" : "${opinion.confidence} percent, ${opinion.description}"}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnstable
                ? AppColors.trustMediumDark.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isUnavailable
                    ? Colors.grey.withValues(alpha: 0.15)
                    : color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isUnavailable ? Colors.grey : color,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  opinion.shortCode,
                  style: TextStyle(
                    color: isUnavailable ? Colors.grey : color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          opinion.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isUnavailable
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isUnstable)
                        _StatusChip(
                          label: 'UNSTABLE',
                          fg: const Color(0xFFE65100),
                          bg: AppColors.alertWarning,
                        ),
                      if (isUnavailable)
                        const _StatusChip(
                          label: 'OFFLINE',
                          fg: Colors.grey,
                          bg: Color(0xFFEEEEEE),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUnavailable ? 'No signal' : opinion.description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isUnavailable ? '—' : '${opinion.confidence}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isUnavailable
                        ? Colors.grey
                        : AppColors.forTrust(opinion.confidence),
                  ),
                ),
                Text(
                  isUnavailable
                      ? 'offline'
                      : '±${_formatRadius(opinion.uncertaintyRadius)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatRadius(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.round()}m';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;

  const _StatusChip({
    required this.label,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
