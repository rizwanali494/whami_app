import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/app_colors.dart';
import '../../core/trust/trust_summary.dart';
import '../../core/widgets/status_panel.dart';
import '../../data/models/position_opinion.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/whami_map_view.dart';
import 'widgets/map_layer_control.dart';

/// Map-first home screen matching the trust-first mockup:
/// full-bleed map, light header, white controls, glanceable trust card.
class MapScreen extends StatefulWidget {
  final WhamiRepository repository;

  const MapScreen({super.key, required this.repository});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Map<String, bool> _layerVisibility = {
    'mapTiles': true,
    'landmarks': true,
    'seamap': true,
    'magnetic': true,
    'opinions': true,
    'uncertainty': true,
  };

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetExtent = 0.42;
  bool _detailsExpanded = true;
  LocationPermission? _permission;

  static const double _sheetInitial = 0.42;
  static const double _sheetMin = 0.26;
  static const double _sheetMax = 0.78;

  WhamiRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    repo.addListener(_onRepoChanged);
    _sheetController.addListener(_onSheetChanged);
    _checkPermission();
  }

  @override
  void dispose() {
    repo.removeListener(_onRepoChanged);
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  void _onSheetChanged() {
    if (!_sheetController.isAttached) return;
    final size = _sheetController.size;
    if ((size - _sheetExtent).abs() < 0.002) return;
    setState(() => _sheetExtent = size);
  }

  Future<void> _checkPermission() async {
    final p = await Geolocator.checkPermission();
    if (mounted) setState(() => _permission = p);
  }

  Future<void> _requestPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }
    if (mounted) setState(() => _permission = p);
  }

  void _recenter() {
    final gps = repo.getPositionOpinions()
        .where((o) => o.sourceType == 'gps' && o.status != 'unavailable')
        .firstOrNull;
    if (gps != null) {
      repo.centerMapOn(gps.latitude, gps.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    final opinions = repo.getPositionOpinions();
    final trustScore = repo.getTrustScore();
    final summary = TrustSummary.fromOpinions(
      trustScore: trustScore,
      opinions: opinions,
      isTracking: repo.isTracking,
    );
    final activePack = repo.getRegionPackById(repo.activePackId);
    final hasPack = activePack != null && activePack.status == 'downloaded';
    final permissionDenied = _permission == LocationPermission.denied ||
        _permission == LocationPermission.deniedForever;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFE8EEF2),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bodyHeight = constraints.maxHeight;
          final sheetTop = bodyHeight * _sheetExtent;

          return Stack(
            children: [
              Positioned.fill(
                child: WhamiMapView(
                  opinions: opinions,
                  layerVisibility: _layerVisibility,
                  repository: repo,
                ),
              ),

              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Column(
                    children: [
                      _BrandHeader(onMenu: () => context.push('/settings')),
                      if (permissionDenied) ...[
                        const SizedBox(height: 10),
                        _FrostedCard(
                          child: StatusPanel.permissionDenied(
                            title: 'Location permission needed',
                            message:
                                'WHAMI needs location access to verify your position.',
                            onAction: _requestPermission,
                          ),
                        ),
                      ] else if (!hasPack && !repo.isTracking) ...[
                        const SizedBox(height: 10),
                        _FrostedCard(
                          child: StatusPanel.empty(
                            title: 'No active region pack',
                            message:
                                'Download an offline pack so landmarks and magnetic witnesses can vote.',
                            actionLabel: 'Open Offline',
                            onAction: () => context.go('/packs'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Positioned(
                right: 14,
                bottom: sheetTop + 72,
                child: Column(
                  children: [
                    MapLayerControl(
                      layerVisibility: _layerVisibility,
                      onLayerToggled: (key, visible) {
                        setState(() => _layerVisibility[key] = visible);
                      },
                      lightStyle: true,
                    ),
                    const SizedBox(height: 10),
                    _RoundMapButton(
                      icon: Icons.my_location,
                      tooltip: 'Recenter',
                      onTap: _recenter,
                    ),
                  ],
                ),
              ),

              // TRACKING LIVE — map-body height × sheet extent (not full screen %).
              Positioned(
                left: 0,
                right: 0,
                bottom: sheetTop + 8,
                child: Center(
                  child: repo.isTracking
                      ? _TrackingLivePill(
                          onTap: () => repo.toggleTracking(),
                        )
                      : _StartTrackingPill(
                          onTap: () {
                            repo.toggleTracking();
                            _checkPermission();
                          },
                        ),
                ),
              ),

              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  final size = notification.extent;
                  if ((size - _sheetExtent).abs() >= 0.002) {
                    setState(() => _sheetExtent = size);
                  }
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetInitial,
                  minChildSize: _sheetMin,
                  maxChildSize: _sheetMax,
                  builder: (context, scrollController) {
                    return _TrustCard(
                      scrollController: scrollController,
                      summary: summary,
                      opinions: opinions,
                      detailsExpanded: _detailsExpanded,
                      bottomInset: bottomInset,
                      onToggleDetails: () {
                        setState(
                          () => _detailsExpanded = !_detailsExpanded,
                        );
                      },
                      onOpenVerify: () => context.go('/verify'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Brand header ─────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  final VoidCallback onMenu;
  const _BrandHeader({required this.onMenu});

  @override
  Widget build(BuildContext context) {
    // Match reference: logo tile (left) + tagline beside it + dark menu (right).
    // Not one combined white app-bar card.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/app_icon.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Verified by the real world.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF5A6570),
              height: 1.25,
              shadows: [
                Shadow(
                  color: Color(0x66FFFFFF),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
        Semantics(
          label: 'Diagnostics and settings',
          button: true,
          child: Material(
            color: AppColors.headerBg,
            shape: const CircleBorder(),
            elevation: 3,
            shadowColor: Colors.black38,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onMenu,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.more_horiz, color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FrostedCard extends StatelessWidget {
  final Widget child;
  const _FrostedCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: child,
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundMapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: AppColors.headerBg, size: 22),
          ),
        ),
      ),
    );
  }
}

class _TrackingLivePill extends StatelessWidget {
  final VoidCallback onTap;
  const _TrackingLivePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tracking live. Tap to stop.',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        elevation: 4,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 9, color: AppColors.trustHigh),
                SizedBox(width: 8),
                Text(
                  'TRACKING LIVE',
                  style: TextStyle(
                    color: AppColors.headerBg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartTrackingPill extends StatelessWidget {
  final VoidCallback onTap;
  const _StartTrackingPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start tracking',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        elevation: 4,
        shadowColor: Colors.black26,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow, color: AppColors.headerBg, size: 20),
                SizedBox(width: 6),
                Text(
                  'START TRACKING',
                  style: TextStyle(
                    color: AppColors.headerBg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Trust bottom card ────────────────────────────────────────────────────────

class _TrustCard extends StatelessWidget {
  final ScrollController scrollController;
  final TrustSummary summary;
  final List<PositionOpinion> opinions;
  final bool detailsExpanded;
  final double bottomInset;
  final VoidCallback onToggleDetails;
  final VoidCallback onOpenVerify;

  const _TrustCard({
    required this.scrollController,
    required this.summary,
    required this.opinions,
    required this.detailsExpanded,
    required this.bottomInset,
    required this.onToggleDetails,
    required this.onOpenVerify,
  });

  @override
  Widget build(BuildContext context) {
    final color = summary.level.color;
    final active = opinions.where((o) => o.status != 'unavailable').toList();

    return Material(
      elevation: 16,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      color: Colors.white,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + bottomInset),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFDDE3EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Glanceable status row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  summary.level == TrustLevel.reliable
                      ? Icons.check
                      : summary.level.icon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.headline,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.headerBg,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Overall score ${summary.score} of 100',
                child: RichText(
                  textAlign: TextAlign.right,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${summary.score}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1,
                        ),
                      ),
                      TextSpan(
                        text: ' / 100',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: color.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Text(
            summary.explanation,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),

          if (summary.level == TrustLevel.caution ||
              summary.level == TrustLevel.unreliable) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onOpenVerify,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                ),
                child: Text(
                  summary.level == TrustLevel.caution
                      ? 'Open Verify'
                      : 'Verify or get offline pack',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],

          const SizedBox(height: 6),
          InkWell(
            onTap: onToggleDetails,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Text(
                    'Verification sources',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.headerBg,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    detailsExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                    size: 26,
                  ),
                ],
              ),
            ),
          ),

          if (detailsExpanded) ...[
            if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Start tracking to collect GPS, landmark, and motion witnesses.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              )
            else
              ...active.map((op) => _SourceRow(opinion: op)),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final PositionOpinion opinion;
  const _SourceRow({required this.opinion});

  IconData get _icon {
    switch (opinion.sourceType) {
      case 'gps':
        return Icons.satellite_alt;
      case 'landmark':
        return Icons.location_on;
      case 'imu':
        return Icons.directions_walk;
      case 'magnetic':
        return Icons.explore;
      case 'sextant':
        return Icons.wb_sunny_outlined;
      default:
        return Icons.shield_outlined;
    }
  }

  String get _title {
    switch (opinion.sourceType) {
      case 'gps':
        return 'GPS';
      case 'landmark':
        return 'Landmark';
      case 'imu':
        return 'Motion';
      case 'magnetic':
        return 'Magnetic';
      case 'sextant':
        return 'Sky';
      default:
        return opinion.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unstable = opinion.status == 'unstable';
    final scoreColor = unstable
        ? AppColors.trustMediumDark
        : AppColors.forTrust(opinion.confidence);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, size: 18, color: AppColors.headerBg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.headerBg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  opinion.description.isEmpty
                      ? (unstable ? 'Unstable' : 'Active')
                      : opinion.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            '${opinion.confidence}%',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: scoreColor,
            ),
          ),
        ],
      ),
    );
  }
}
