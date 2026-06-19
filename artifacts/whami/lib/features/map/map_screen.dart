import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/connectivity_status.dart';
import '../../data/repositories/whami_mock_repository.dart';
import 'widgets/whami_map_view.dart';
import 'widgets/trust_badge.dart';
import 'widgets/scenario_selector.dart';
import 'widgets/position_opinion_card.dart';
import 'widgets/map_layer_control.dart';

class MapScreen extends StatefulWidget {
  final WhamiMockRepository repository;

  const MapScreen({super.key, required this.repository});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _selectedScenario = 0;

  final Map<String, bool> _layerVisibility = {
    'mapTiles': true,
    'landmarks': true,
    'seamap': true,
    'magnetic': true,
    'opinions': true,
    'uncertainty': true,
  };

  WhamiMockRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    repo.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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

    // Connectivity UI Helpers
    final currentMode = repo.connectivityMode;
    final String modeLabel = currentMode.name.toUpperCase();
    final Color modeColor = currentMode == ConnectivityMode.online
        ? AppColors.trustHigh
        : currentMode == ConnectivityMode.offline
        ? AppColors.whami
        : AppColors.trustLow;

    final activePack = repo.getRegionPackById(repo.activePackId);
    final activePackName = activePack?.name ?? 'No Pack';
    final hasPack = activePack != null && activePack.status == 'downloaded';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            titleSpacing: 16,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'WHAMI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  'Verified by the real world.',
                  style: TextStyle(
                    color: Color(0xFF90A4AE),
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TrustBadge(trustScore: trustScore),
              ),
            ],
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
                    'Multi-Source Consensus View',
                    style: TextStyle(
                      fontSize: 15,
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
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasPack
                            ? '$activePackName active'
                            : 'No offline packs active',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: modeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: modeColor.withOpacity(0.4)),
                        ),
                        child: Text(
                          modeLabel,
                          style: TextStyle(
                            fontSize: 9,
                            color: modeColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Real MapLibre GL map with stacked overlays ──────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 320,
                      child: Stack(
                        children: [
                          WhamiMapView(
                            opinions: opinions,
                            layerVisibility: _layerVisibility,
                            repository: repo,
                          ),

                          // Layer toggler floating panel (Bottom-Right)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: MapLayerControl(
                              layerVisibility: _layerVisibility,
                              onLayerToggled: (key, visible) {
                                setState(() {
                                  _layerVisibility[key] = visible;
                                });
                              },
                            ),
                          ),

                          // Live Tracking fab (Top-Right)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: FloatingActionButton.small(
                              heroTag: 'live_tracking_fab',
                              onPressed: () => repo.toggleTracking(),
                              backgroundColor: repo.isTracking
                                  ? AppColors.whami
                                  : AppColors.headerBg,
                              tooltip: repo.isTracking
                                  ? 'Stop Live Tracking'
                                  : 'Start Live Tracking',
                              child: Icon(
                                repo.isTracking
                                    ? Icons.gps_fixed
                                    : Icons.gps_off,
                                color: repo.isTracking
                                    ? AppColors.headerBg
                                    : Colors.white,
                                size: 18,
                              ),
                            ),
                          ),

                          // Live status indicator (Bottom-Left)
                          if (repo.isTracking)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.headerBg.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.whami.withOpacity(0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.whami,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'TRACKING LIVE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
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
                    message: alertMessage,
                    scenario: scenario.id,
                  ),
                ),

                // ── Position opinions list ────────────────────────────────
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Text(
                    'Position Opinions (Cross-Check)',
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
                        .map(
                          (op) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: PositionOpinionCard(opinion: op),
                          ),
                        )
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
    final bool isWarning =
        scenario == 'magnetic_interference' ||
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
