import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/trust_event.dart';

class AlertEventCard extends StatelessWidget {
  final TrustEvent event;

  const AlertEventCard({super.key, required this.event});

  IconData _iconFor(String name) {
    switch (name) {
      case 'gps_off': return Icons.gps_off;
      case 'location_on': return Icons.location_on;
      case 'explore_off': return Icons.explore_off;
      case 'inventory_2': return Icons.inventory_2;
      case 'wb_sunny': return Icons.wb_sunny;
      case 'directions_walk': return Icons.directions_walk;
      case 'satellite_alt': return Icons.satellite_alt;
      case 'shield': return Icons.shield;
      default: return Icons.notifications;
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return AppColors.alertCriticalBorder;
      case 'warning': return AppColors.alertWarningBorder;
      default: return AppColors.alertInfoBorder;
    }
  }

  Color _severityBg(String severity) {
    switch (severity) {
      case 'critical': return AppColors.alertCritical;
      case 'warning': return AppColors.alertWarning;
      default: return AppColors.alertInfo;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'critical': return 'CRITICAL';
      case 'warning': return 'WARNING';
      default: return 'INFO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(event.severity);
    final bg = _severityBg(event.severity);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Icon(_iconFor(event.iconName), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: color.withOpacity(0.5)),
                        ),
                        child: Text(
                          _severityLabel(event.severity),
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.time,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
