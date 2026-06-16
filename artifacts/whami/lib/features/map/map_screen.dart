import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_mock_repository.dart';
import 'widgets/mock_map_canvas.dart';
import 'widgets/trust_badge.dart';
import 'widgets/scenario_selector.dart';
import 'widgets/position_opinion_card.dart';

class MapScreen extends StatefulWidget {
  final WhamiMockRepository repository;

  const MapScreen({super.key, required this.repository});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _selectedScenario = 0;

  WhamiMockRepository get repo => widget.repository;

  void _onScenarioChanged(int index) {
    setState(() {
      _selectedScenario = index;
      repo.setScenario(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scenario = repo.activeScenario;
    final opinions = repo.getPositionOpinions();
    final trustScore = repo.getTrustScore();
    final alertMessage = repo.getAlertMessage();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            expandedHeight: 100,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'WHAMI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                          Text(
                            'Verified by the real world.',
                            style: TextStyle(
                              color: Color(0xFF90A4AE),
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TrustBadge(trustScore: trustScore),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Scenario selector
                const SizedBox(height: 14),
                ScenarioSelector(
                  scenarios: repo.scenarios,
                  selectedIndex: _selectedScenario,
                  onChanged: _onScenarioChanged,
                ),

                // Map title
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: const Text(
                    'One-view position opinions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

                // Map canvas
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 240,
                    child: MockMapCanvas(opinions: opinions),
                  ),
                ),

                // Map legend
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: opinions
                        .map((op) => _LegendItem(opinion: op))
                        .toList(),
                  ),
                ),

                // Alert card
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _AlertCard(message: alertMessage, scenario: scenario.id),
                ),

                // Opinions list title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: const Text(
                    'Position Opinions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

                // Opinions list
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: opinions
                        .map((op) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: PositionOpinionCard(opinion: op),
                            ))
                        .toList(),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final dynamic opinion;

  const _LegendItem({required this.opinion});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forSource(opinion.sourceType as String);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              opinion.shortCode as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          opinion.name as String,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final String message;
  final String scenario;

  const _AlertCard({required this.message, required this.scenario});

  @override
  Widget build(BuildContext context) {
    final bool isCritical = scenario == 'gps_spoof';
    final bool isWarning = scenario == 'magnetic_interference' ||
        scenario == 'gps_lost' ||
        scenario == 'night';

    Color bg = AppColors.alertInfo;
    Color border = AppColors.alertInfoBorder;
    Color icon = AppColors.alertInfoBorder;
    IconData iconData = Icons.info_outline;

    if (isCritical) {
      bg = AppColors.alertCritical;
      border = AppColors.alertCriticalBorder;
      icon = AppColors.alertCriticalBorder;
      iconData = Icons.warning_amber_rounded;
    } else if (isWarning) {
      bg = AppColors.alertWarning;
      border = AppColors.alertWarningBorder;
      icon = AppColors.alertWarningBorder;
      iconData = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, color: icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
