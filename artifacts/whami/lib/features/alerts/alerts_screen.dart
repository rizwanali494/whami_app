import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/alert_event_card.dart';

class AlertsScreen extends StatelessWidget {
  final WhamiRepository repository;

  const AlertsScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    final events = repository.getTrustEvents();
    final criticalCount = events.where((e) => e.severity == 'critical').length;
    final warningCount = events.where((e) => e.severity == 'warning').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            title: const Text(
              'Alerts & History',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              if (criticalCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    backgroundColor: AppColors.alertCritical,
                    label: Text(
                      '$criticalCount Critical',
                      style: const TextStyle(
                        color: AppColors.alertCriticalBorder,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              if (warningCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Chip(
                    backgroundColor: AppColors.alertWarning,
                    label: Text(
                      '$warningCount Warning',
                      style: const TextStyle(
                        color: AppColors.alertWarningBorder,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _SummaryChip(
                        count: criticalCount,
                        label: 'Critical',
                        color: AppColors.alertCriticalBorder,
                        bg: AppColors.alertCritical,
                      ),
                      const SizedBox(width: 10),
                      _SummaryChip(
                        count: warningCount,
                        label: 'Warning',
                        color: AppColors.alertWarningBorder,
                        bg: AppColors.alertWarning,
                      ),
                      const SizedBox(width: 10),
                      _SummaryChip(
                        count: events.length - criticalCount - warningCount,
                        label: 'Info',
                        color: AppColors.alertInfoBorder,
                        bg: AppColors.alertInfo,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Recent Trust Events',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...events.map((e) => AlertEventCard(event: e)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final Color bg;

  const _SummaryChip({
    required this.count,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
