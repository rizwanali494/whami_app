import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/sensor_status.dart';

class SensorCard extends StatelessWidget {
  final SensorStatus sensor;
  final bool isFusion;

  const SensorCard({
    super.key,
    required this.sensor,
    this.isFusion = false,
  });

  IconData _iconFor(String name) {
    switch (name) {
      case 'satellite_alt': return Icons.satellite_alt;
      case 'explore': return Icons.explore;
      case 'directions_walk': return Icons.directions_walk;
      case 'rotate_90_degrees_ccw': return Icons.rotate_90_degrees_ccw;
      case 'compress': return Icons.compress;
      case 'wb_sunny': return Icons.wb_sunny;
      case 'hub': return Icons.hub;
      default: return Icons.sensors;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active': return AppColors.trustHigh;
      case 'available': return AppColors.gps;
      case 'unstable': return AppColors.alertWarningBorder;
      case 'unavailable': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active': return 'Active';
      case 'available': return 'Available';
      case 'unstable': return 'Unstable';
      case 'unavailable': return 'Offline';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(sensor.status);
    final confidenceColor = AppColors.forTrust(sensor.confidence);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isFusion
                        ? AppColors.headerBg
                        : statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(sensor.iconName),
                    color: isFusion ? AppColors.whami : statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sensor.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _statusLabel(sensor.status),
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sensor.confidence == 0
                          ? '—'
                          : '${sensor.confidence}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: sensor.confidence == 0
                            ? Colors.grey
                            : confidenceColor,
                      ),
                    ),
                    Text(
                      'confidence',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            if (sensor.confidence > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: sensor.confidence / 100,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(confidenceColor),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Latest value
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.data_object,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sensor.latestValue,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Health message
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  sensor.status == 'unstable' || sensor.status == 'unavailable'
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  size: 14,
                  color: statusColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sensor.healthMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: sensor.status == 'unstable'
                          ? const Color(0xFFE65100)
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
