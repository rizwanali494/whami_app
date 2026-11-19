import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/trust/trust_summary.dart';
import '../../core/widgets/status_panel.dart';
import '../../data/repositories/whami_repository.dart';
import '../whami_air/air_preferences.dart';
import '../whami_air/widgets/air_trust_strip.dart';
import 'widgets/whami_map_view.dart';
import 'widgets/map_layer_control.dart';
import 'widgets/spoof_alarm_banner.dart';
import 'widgets/witness_crossfire_panel.dart';
import 'widgets/flight_plan_panel.dart';
import 'widgets/map_gps_hud.dart';
import 'widgets/compact_trust_panel.dart';
import 'widgets/map_style_sheet.dart';
import 'widgets/trust_copilot_strip.dart';
import 'widgets/truth_mode_panel.dart';
import 'widgets/witness_mesh_panel.dart';
import '../../core/theme/whami_aviation.dart';
import '../../core/config/map_basemap_style.dart';

/// Map-first aviation home: translucent chrome, compact trust card, GNSS HUD.
class MapScreen extends StatefulWidget {
  final WhamiRepository repository;

  const MapScreen({super.key, required this.repository});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final Map<String, bool> _layerVisibility = {
    'mapTiles': true,
    'landmarks': true,
    'seamap': true,
    'magnetic': true,
    'opinions': true,
    'uncertainty': true,
    'rangeRings': true,
    'spoofHeat': false,
  };

  LocationPermission? _permission;
  bool? _locationServicesEnabled;
  bool _crossfireDismissed = false;
  bool _wasGhostPinVisible = false;
  bool _lieLineDismissed = false;
  bool _permissionBannerDismissed = false;
  bool _locationBannerDismissed = false;
  bool _didAutoStart = false;
  bool _flightPlanPanelOpen = false;
  bool _trustExpanded = false;
  bool _hudExpanded = false;
  bool _truthPanelOpen = false;
  bool _meshPanelOpen = false;

  WhamiRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.addListener(_onRepoChanged);
    _checkPermission();
    // GpsService may show the system prompt in parallel; re-read after it settles.
    Future<void>.delayed(const Duration(seconds: 2), _checkPermission);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoStartTracking());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLocationStatus(retryGps: true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // George demo: leaving the app restores GPS if the user toggled it off.
      repo.restoreGpsOnLeave();
    }
  }

  Future<void> _autoStartTracking() async {
    if (_didAutoStart || !mounted) return;
    _didAutoStart = true;
    await _checkPermission();
    if (!mounted) return;
    var p = _permission ?? await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
      if (mounted) setState(() => _permission = p);
    }
    if (!mounted) return;
    if (!repo.isTracking) {
      repo.ensureTracking();
    }
  }

  void _onRepoChanged() {
    if (!mounted) return;
    // Only auto-reopen Crossfire on a *new* Ghost Pin episode — not on every
    // GPS tick (that was undoing the X / dismiss immediately).
    final ghostNow = repo.showGhostPin;
    if (ghostNow && !_wasGhostPinVisible) {
      _crossfireDismissed = false;
      _lieLineDismissed = false;
    }
    if (!ghostNow && !repo.crossfire.visible) {
      _crossfireDismissed = false;
    }
    if (!ghostNow) {
      _lieLineDismissed = false;
    }
    _wasGhostPinVisible = ghostNow;
    // If GPS is already flowing but the banner still thinks we're denied,
    // the system grant landed via GpsService — refresh permission state.
    final denied = _permission == LocationPermission.denied ||
        _permission == LocationPermission.deniedForever;
    if (denied &&
        repo.getPositionOpinions().any(
          (o) => o.sourceType == 'gps' && o.status != 'unavailable',
        )) {
      _checkPermission();
    }
    setState(() {});
  }

  Future<void> _checkPermission() async {
    await _refreshLocationStatus(retryGps: false);
  }

  Future<void> _refreshLocationStatus({required bool retryGps}) async {
    final services = await Geolocator.isLocationServiceEnabled();
    final p = await Geolocator.checkPermission();
    if (!mounted) return;
    final changed =
        services != _locationServicesEnabled || p != _permission;
    if (changed) {
      setState(() {
        _locationServicesEnabled = services;
        _permission = p;
        if (services) _locationBannerDismissed = false;
        if (p == LocationPermission.whileInUse ||
            p == LocationPermission.always) {
          _permissionBannerDismissed = false;
        }
      });
    }
    if (retryGps &&
        services &&
        (p == LocationPermission.whileInUse ||
            p == LocationPermission.always)) {
      await repo.retryLocation();
    }
  }

  Future<void> _requestPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    } else if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      p = await Geolocator.checkPermission();
    }
    if (mounted) setState(() => _permission = p);
    if (p == LocationPermission.whileInUse ||
        p == LocationPermission.always) {
      await repo.retryLocation();
    }
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
    // Resume lifecycle also retries; call once here for responsiveness.
    await _refreshLocationStatus(retryGps: true);
  }

  Future<void> _retryLocation() async {
    setState(() {
      _locationBannerDismissed = false;
      _permissionBannerDismissed = false;
    });
    final services = await Geolocator.isLocationServiceEnabled();
    if (!services) {
      await _openLocationSettings();
      return;
    }
    final p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      await _requestPermission();
      return;
    }
    await repo.retryLocation();
    if (mounted) setState(() {});
  }

  void _recenter() {
    // Follow / center on the blue GPS pin (where you are).
    final gps = repo.getPositionOpinions()
        .where((o) => o.sourceType == 'gps' && o.status != 'unavailable')
        .firstOrNull;
    if (gps != null) {
      repo.centerMapOn(gps.latitude, gps.longitude);
      return;
    }
    // Fallback: trusted fuse only when it is a real fix.
    final trusted = repo.getTrustedPosition();
    if (trusted.status == 'unavailable') return;
    repo.centerMapOn(trusted.latitude, trusted.longitude);
  }

  void _collapseTrustPanel() {
    if (_trustExpanded) setState(() => _trustExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final opinions = repo.getPositionOpinions();
    final trustScore = repo.getTrustScore();
    final summary = TrustSummary.fromOpinions(
      trustScore: trustScore,
      opinions: opinions,
      isTracking: repo.isTracking,
      gnssSuspicious: repo.gnssSuspicious,
    );
    final hasLiveGps = opinions.any(
      (o) => o.sourceType == 'gps' && o.status != 'unavailable',
    );
    final servicesOff = _locationServicesEnabled == false;
    // Don't keep the lock card up after the user already granted (stale check
    // or grant that came through GpsService instead of this screen).
    final permissionDenied = !hasLiveGps &&
        !servicesOff &&
        (_permission == LocationPermission.denied ||
            _permission == LocationPermission.deniedForever);
    final showLocationServicesBanner =
        servicesOff && !hasLiveGps && !_locationBannerDismissed;
    final showWaitingForFix = repo.isTracking &&
        repo.gpsEnabled &&
        !hasLiveGps &&
        !servicesOff &&
        !permissionDenied &&
        !_locationBannerDismissed;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final airMode = context.watch<AirPreferences>().airModeEnabled;
    final chromeBottom = bottomInset + 12;

    return Scaffold(
      backgroundColor: WhamiAviation.navy,
      body: LayoutBuilder(
        builder: (context, constraints) {
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
                  // Leave a clear lane for the right-side map FABs so overlay
                  // close controls are never covered by layers/GPS buttons.
                  padding: const EdgeInsets.fromLTRB(14, 8, 72, 0),
                  child: Column(
                    children: [
                      _BrandHeader(onMenu: () => context.push('/settings')),
                      if (repo.showSpoofAlarm) ...[
                        const SizedBox(height: 10),
                        SpoofAlarmBanner(
                          message: repo.alertMessage,
                          onVerify: () => context.go('/verify'),
                          onDismiss: repo.dismissSpoofAlarm,
                        ),
                      ],
                      if (repo.showGhostPin &&
                          repo.lieDistanceM != null &&
                          !_lieLineDismissed &&
                          !repo.flightPlanEditMode &&
                          !_flightPlanPanelOpen) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Material(
                            color: const Color(0xFFB71C1C),
                            borderRadius: BorderRadius.circular(22),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    repo.lieDistanceM! >= 1000
                                        ? 'Lie line · ${(repo.lieDistanceM! / 1000).toStringAsFixed(1)} km'
                                        : 'Lie line · ${repo.lieDistanceM!.round()} m',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Dismiss',
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    onPressed: () => setState(
                                      () => _lieLineDismissed = true,
                                    ),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (repo.hasRealWorldLock) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: RealWorldLockChip(
                            landmarkName: repo.landmarkAnchor!.name,
                            onUnlock: repo.clearLandmarkAnchor,
                            onTap: () => context.go('/verify'),
                          ),
                        ),
                      ],
                      if (repo.crossfire.visible &&
                          !_crossfireDismissed &&
                          !repo.flightPlanEditMode &&
                          !_flightPlanPanelOpen) ...[
                        const SizedBox(height: 10),
                        WitnessCrossfirePanel(
                          crossfire: repo.crossfire,
                          onDismiss: () =>
                              setState(() => _crossfireDismissed = true),
                        ),
                      ],
                      // Compact banner only when placing pins with panel closed
                      // (panel already has Done / Place controls — don't stack both).
                      if (repo.flightPlanEditMode && !_flightPlanPanelOpen) ...[
                        const SizedBox(height: 10),
                        _RoutePinBanner(
                          pinCount:
                              repo.activeFlightPlan?.waypoints.length ?? 0,
                          onDone: () {
                            repo.setFlightPlanEditMode(false);
                            unawaited(repo.saveActiveFlightPlan());
                          },
                          onOpenPanel: () =>
                              setState(() => _flightPlanPanelOpen = true),
                        ),
                      ],
                      if (_flightPlanPanelOpen) ...[
                        const SizedBox(height: 10),
                        FlightPlanPanel(
                          repository: repo,
                          onClose: () =>
                              setState(() => _flightPlanPanelOpen = false),
                        ),
                      ],
                      if (_truthPanelOpen) ...[
                        const SizedBox(height: 10),
                        TruthModePanel(
                          repository: repo,
                          onClose: () =>
                              setState(() => _truthPanelOpen = false),
                        ),
                      ],
                      if (_meshPanelOpen) ...[
                        const SizedBox(height: 10),
                        WitnessMeshPanel(
                          repository: repo,
                          onClose: () =>
                              setState(() => _meshPanelOpen = false),
                        ),
                      ],
                      if (repo.currentAdvisory != null &&
                          !repo.flightPlanEditMode &&
                          !_flightPlanPanelOpen &&
                          !_truthPanelOpen &&
                          !_meshPanelOpen) ...[
                        const SizedBox(height: 10),
                        TrustCopilotStrip(advisory: repo.currentAdvisory!),
                      ],
                      // Keep map clear while routing — hide Air strip overlays.
                      if (airMode &&
                          !repo.flightPlanEditMode &&
                          !_flightPlanPanelOpen) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => context.push('/air'),
                          child: AirTrustStrip(
                            snapshot: repo.airTrust,
                            compact: true,
                          ),
                        ),
                      ],
                      if (showLocationServicesBanner) ...[
                        const SizedBox(height: 10),
                        _FrostedCard(
                          child: Stack(
                            children: [
                              StatusPanel.failure(
                                title: 'Location services off',
                                message:
                                    'Turn on device location to get a GPS fix. '
                                    'Sensors (compass, motion, baro) keep working.',
                                actionLabel: 'Open location settings',
                                onAction: _openLocationSettings,
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed: () => setState(
                                    () => _locationBannerDismissed = true,
                                  ),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (permissionDenied && !_permissionBannerDismissed) ...[
                        const SizedBox(height: 10),
                        _FrostedCard(
                          child: Stack(
                            children: [
                              StatusPanel.permissionDenied(
                                title: 'Location permission needed',
                                message:
                                    'WHAMI needs location access to verify your position. '
                                    'Sensors keep working without GPS.',
                                actionLabel: _permission ==
                                        LocationPermission.deniedForever
                                    ? 'Open settings'
                                    : 'Allow location',
                                onAction: _requestPermission,
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed: () => setState(
                                    () => _permissionBannerDismissed = true,
                                  ),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (showWaitingForFix) ...[
                        const SizedBox(height: 10),
                        _FrostedCard(
                          child: Stack(
                            children: [
                              StatusPanel.loading(
                                title: 'Waiting for GPS fix',
                                message: repo.gpsStatusMessage,
                              ),
                              Positioned(
                                top: 4,
                                right: 48,
                                child: TextButton(
                                  onPressed: _retryLocation,
                                  child: const Text('Retry'),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Dismiss',
                                  onPressed: () => setState(
                                    () => _locationBannerDismissed = true,
                                  ),
                                  icon: const Icon(Icons.close, size: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Online streets always show without a pack — do not
                      // cover the map with a "download pack" modal.
                    ],
                  ),
                ),
              ),

              // Unified right toolbar — layers, basemap style, route, GPS, center, replay.
              Positioned(
                right: 14,
                bottom: chromeBottom + 168,
                child: Column(
                  children: [
                    if (!repo.flightPlanEditMode && !_flightPlanPanelOpen) ...[
                      MapLayerControl(
                        layerVisibility: _layerVisibility,
                        onLayerToggled: (key, visible) {
                          setState(() => _layerVisibility[key] = visible);
                        },
                        onOpenMapStyle: () => showMapStyleSheet(
                          context: context,
                          current: repo.mapBasemapStyle,
                          onSelected: repo.setMapBasemapStyle,
                        ),
                        mapStyleLabel: repo.mapBasemapStyle.shortLabel,
                      ),
                      const SizedBox(height: 10),
                      _RoundMapButton(
                        icon: Icons.map_outlined,
                        tooltip:
                            'Map style · ${repo.mapBasemapStyle.shortLabel}',
                        onTap: () => showMapStyleSheet(
                          context: context,
                          current: repo.mapBasemapStyle,
                          onSelected: repo.setMapBasemapStyle,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _RoundMapButton(
                      icon: Icons.route,
                      tooltip: repo.flightPlanEditMode
                          ? 'Placing route pins — tap map'
                          : 'Plan travel route',
                      onTap: () {
                        setState(() {
                          if (_flightPlanPanelOpen) {
                            _flightPlanPanelOpen = false;
                          } else {
                            _flightPlanPanelOpen = true;
                            _truthPanelOpen = false;
                            _meshPanelOpen = false;
                            if (!repo.flightPlanEditMode) {
                              repo.beginTravelRoutePlanning();
                            }
                            _collapseTrustPanel();
                          }
                        });
                      },
                    ),
                    if (!repo.flightPlanEditMode && !_flightPlanPanelOpen) ...[
                      const SizedBox(height: 10),
                      _RoundMapButton(
                        icon: Icons.compare_arrows,
                        tooltip: 'Truth Mode',
                        onTap: () => setState(() {
                          _truthPanelOpen = !_truthPanelOpen;
                          _meshPanelOpen = false;
                          _collapseTrustPanel();
                        }),
                      ),
                      const SizedBox(height: 10),
                      _RoundMapButton(
                        icon: Icons.devices,
                        tooltip: 'Witness Mesh',
                        onTap: () => setState(() {
                          _meshPanelOpen = !_meshPanelOpen;
                          _truthPanelOpen = false;
                          _collapseTrustPanel();
                        }),
                      ),
                      const SizedBox(height: 10),
                      if (repo.isTracking) ...[
                        _RoundMapButton(
                          icon: repo.gpsEnabled
                              ? Icons.gps_fixed
                              : Icons.gps_off,
                          tooltip: repo.gpsEnabled
                              ? 'Turn GPS off (sensors only)'
                              : 'Turn GPS on',
                          onTap: () =>
                              repo.setGpsEnabled(!repo.gpsEnabled),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _RoundMapButton(
                        icon: Icons.my_location,
                        tooltip: 'Center on GPS',
                        onTap: _recenter,
                      ),
                      const SizedBox(height: 10),
                      _RoundMapButton(
                        icon: Icons.timeline,
                        tooltip: 'Replay',
                        onTap: () => context.push('/timeline'),
                      ),
                    ],
                  ],
                ),
              ),

              // GNSS HUD + compact trust — ~70% map stays clear.
              if (!repo.flightPlanEditMode && !_flightPlanPanelOpen)
                Positioned(
                  left: 14,
                  right: 72,
                  bottom: chromeBottom,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CompactTrustPanel(
                          summary: summary,
                          opinions: opinions,
                          expanded: _trustExpanded,
                          onToggle: () => setState(
                            () => _trustExpanded = !_trustExpanded,
                          ),
                          onOpenVerify: () => context.go('/verify'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: MapGpsHud(
                          reading: repo.liveGpsReading,
                          gpsEnabled: repo.gpsEnabled,
                          isTracking: repo.isTracking,
                          expanded: _hudExpanded,
                          onToggleExpand: () => setState(
                            () => _hudExpanded = !_hudExpanded,
                          ),
                          onStopTracking: repo.isTracking
                              ? () => repo.toggleTracking()
                              : null,
                          onStartTracking: !repo.isTracking
                              ? () {
                                  repo.toggleTracking();
                                  _checkPermission();
                                }
                              : null,
                        ),
                      ),
                    ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: WhamiAviation.navy.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAMI',
                  style: TextStyle(
                    color: WhamiAviation.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Verified by the real world.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            label: 'Diagnostics and settings',
            button: true,
            child: Material(
              color: Colors.white.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onMenu,
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.more_horiz, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedCard extends StatelessWidget {
  final Widget child;
  const _FrostedCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x140A1628)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
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
    final size = WhamiLayout.mapFabSize(context);
    final iconSize = WhamiLayout.mapFabIcon(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: WhamiAviation.charcoal.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: WhamiAviation.cyan, size: iconSize),
          ),
        ),
      ),
    );
  }
}

/// Live banner while placing pins ahead on the travel route.
class _RoutePinBanner extends StatelessWidget {
  final int pinCount;
  final VoidCallback onDone;
  final VoidCallback onOpenPanel;

  const _RoutePinBanner({
    required this.pinCount,
    required this.onDone,
    required this.onOpenPanel,
  });

  @override
  Widget build(BuildContext context) {
    final hint = pinCount == 0
        ? 'Tap the map to set Origin'
        : pinCount == 1
            ? 'Tap ahead for the next waypoint'
            : '$pinCount pins set · tap for Destination';

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1565C0).withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onOpenPanel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ROUTING',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        hint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: onDone,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
