import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_mock_repository.dart';
import 'widgets/whami_map_view.dart';
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
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
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
                // ── Scenario selector ──────────────────────────────────────
                const SizedBox(height: 14),
                ScenarioSelector(
                  scenarios: repo.scenarios,
                  selectedIndex: _selectedScenario,
                  onChanged: _onScenarioChanged,
                ),

                // ── Map title ──────────────────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'One-view position opinions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

                // ── Region pack label ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      const Text(
                        'SF Bay region pack loaded',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A3A2A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OFFLINE',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Real MapLibre GL map ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 280,
                      child: WhamiMapView(opinions: opinions),
                    ),
                  ),
                ),

                // ── Legend ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: MapLegendRow(opinions: opinions),
                ),

                // ── Alert card ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _AlertCard(
                      message: alertMessage, scenario: scenario.id),
                ),

                // ── Position opinions list ────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Text(
                    'Position Opinions',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

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

// ── Alert card ────────────────────────────────────────────────────────────────

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
    Color iconColor = AppColors.alertInfoBorder;
    IconData iconData = Icons.info_outline;

    if (isCritical) {
      bg = AppColors.alertCritical;
      border = AppColors.alertCriticalBorder;
      iconColor = AppColors.alertCriticalBorder;
      iconData = Icons.warning_amber_rounded;
    } else if (isWarning) {
      bg = AppColors.alertWarning;
      border = AppColors.alertWarningBorder;
      iconColor = AppColors.alertWarningBorder;
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
          Icon(iconData, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
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
