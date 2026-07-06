import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class TrustBadge extends StatelessWidget {
  final int trustScore;

  const TrustBadge({super.key, required this.trustScore});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forTrust(trustScore);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            'TRUST $trustScore%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
