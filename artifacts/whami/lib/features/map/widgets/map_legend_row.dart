import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class MapLegendRow extends StatelessWidget {
  final List<PositionOpinion> opinions;

  const MapLegendRow({super.key, required this.opinions});

  @override
  Widget build(BuildContext context) {
    if (opinions.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opinions.map((op) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _colorForSource(op.sourceType),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  op.name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _colorForSource(String sourceType) {
    switch (sourceType) {
      case 'whami':
        return AppColors.whami;
      case 'gps':
        return AppColors.gps;
      case 'landmark':
        return AppColors.landmark;
      case 'magnetic':
        return AppColors.magnetic;
      case 'sextant':
        return AppColors.sextant;
      case 'imu':
        return AppColors.imu;
      default:
        return Colors.white;
    }
  }
}
