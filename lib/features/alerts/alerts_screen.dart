import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/status_panel.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/alert_event_card.dart';

class AlertsScreen extends StatelessWidget {
  final WhamiRepository repository;

  const AlertsScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final events = repository.getTrustEvents();
        final criticalCount =
            events.where((e) => e.severity == 'critical').length;
        final warningCount =
            events.where((e) => e.severity == 'warning').length;
        final live = events
            .where((e) =>
                e.isOngoing &&
                (e.severity == 'warning' || e.severity == 'critical'))
            .toList();

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              const SliverAppBar(
                pinned: true,
                title: Text('Activity'),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            color: AppColors.trustMediumDark,
                            bg: AppColors.alertWarning,
                          ),
                          const SizedBox(width: 10),
                          _SummaryChip(
                            count:
                                events.length - criticalCount - warningCount,
                            label: 'Info',
                            color: AppColors.alertInfoBorder,
                            bg: AppColors.alertInfo,
                          ),
                        ],
                      ),
                    ),
                    if (live.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'Needs attention',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      ...live.map((e) => AlertEventCard(event: e)),
                      const SizedBox(height: 8),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'History',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (events.isEmpty)
                      StatusPanel.empty(
                        title: 'No trust history yet',
                        message:
                            'Start tracking on Map to record consensus changes, GPS events, and verifies.',
                      )
                    else
                      ...events.map((e) => AlertEventCard(event: e)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        constraints: const BoxConstraints(minHeight: 64),
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
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
