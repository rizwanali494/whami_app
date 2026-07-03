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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUnstable
              ? AppColors.alertWarningBorder.withValues(alpha: 0.5)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          // Source badge
          Container(
            width: 32,
            height: 32,
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
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      opinion.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isUnavailable
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isUnstable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.alertWarning,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNSTABLE',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFE65100),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (isUnavailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNAVAIL.',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isUnavailable ? 'No signal' : opinion.description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Confidence
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isUnavailable ? '—' : '${opinion.confidence}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
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
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
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
