import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/whami_aviation.dart';
import '../../core/widgets/status_panel.dart';
import '../../core/widgets/whami_chrome.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/alert_event_card.dart';

Future<void> _exportEvidence(BuildContext context, WhamiRepository repo) async {
  try {
    final file = await repo.exportEvidencePack();
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'WHAMI Evidence Pack — verified by the real world.',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${file.path.split('/').last}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}

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
        final pad = WhamiLayout.pagePad(context);

        return Scaffold(
          backgroundColor: WhamiAviation.lightWash,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: WhamiAviation.navy,
                pinned: true,
                automaticallyImplyLeading: false,
                expandedHeight: 72,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACTIVITY',
                      style: TextStyle(
                        color: WhamiAviation.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Trust history',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
                      child: WhamiGlassCard(
                        light: true,
                        onTap: () => context.push('/timeline'),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: WhamiAviation.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.timeline,
                                color: WhamiAviation.amber,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Trust Timeline Replay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: WhamiAviation.lightInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    repository.trustTimeline.isEmpty
                                        ? 'Start tracking to record evidence'
                                        : '${repository.trustTimeline.length} samples',
                                    style: WhamiAviation.body(
                                      color: WhamiAviation.lightMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: WhamiAviation.lightMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                      child: WhamiGlassCard(
                        light: true,
                        onTap: repository.trustTimeline.isEmpty
                            ? null
                            : () => _exportEvidence(context, repository),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: WhamiAviation.success
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.folder_zip_outlined,
                                color: WhamiAviation.success,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Export Evidence Pack',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: WhamiAviation.lightInk,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    repository.trustTimeline.isEmpty
                                        ? 'Record a session first'
                                        : 'ZIP timeline + summary',
                                    style: WhamiAviation.body(
                                      color: WhamiAviation.lightMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.ios_share,
                              color: WhamiAviation.lightMuted,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
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
                      WhamiSectionLabel('Needs attention', light: true),
                      ...live.map((e) => AlertEventCard(event: e)),
                    ],
                    WhamiSectionLabel('History', light: true),
                    if (events.isEmpty)
                      StatusPanel.empty(
                        title: 'No trust history yet',
                        message:
                            'Start tracking on Map to record consensus changes, GPS events, and verifies.',
                      )
                    else
                      ...events.map((e) => AlertEventCard(event: e)),
                    const SizedBox(height: 96),
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
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
