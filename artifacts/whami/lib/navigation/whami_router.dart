import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/repositories/whami_repository.dart';
import '../data/services/gps_service.dart';
import '../data/services/magnetometer_service.dart';
import '../data/services/imu_service.dart';
import '../data/services/barometer_service.dart';
import '../data/services/camera_service.dart';
import '../data/services/sky_service.dart';
import '../data/services/sensor_manager.dart';
import '../data/services/region_pack_storage.dart';
import '../data/services/region_pack_downloader.dart';
import '../data/services/position_matcher.dart';
import '../data/services/trust_fusion_engine.dart';
import '../data/services/trust_event_log.dart';
import '../features/map/map_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/sensors/sensors_screen.dart';
import '../features/region_packs/region_pack_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/offline_banner.dart';

final gpsService = GpsService();
final magnetometerService = MagnetometerService();
final imuService = ImuService();
final barometerService = BarometerService();
final cameraService = CameraService();
final skyService = SkyService();

final sensorManager = SensorManager(
  gpsService: gpsService,
  magnetometerService: magnetometerService,
  imuService: imuService,
  barometerService: barometerService,
  cameraService: cameraService,
  skyService: skyService,
);

final storage = RegionPackStorage();
final downloader = RegionPackDownloader(storage: storage);
final matcher = PositionMatcher();
final fusionEngine = TrustFusionEngine();
final eventLog = TrustEventLog();

final whamiRepo = WhamiRepository(
  sensors: sensorManager,
  storage: storage,
  downloader: downloader,
  matcher: matcher,
  fusionEngine: fusionEngine,
  eventLog: eventLog,
);

final whamiRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Splash screen — navigates to /map after delay
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),

    // Main shell with bottom navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          _WhamiShell(shell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (_, __) => MapScreen(repository: whamiRepo),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scan',
              builder: (_, __) => ScanScreen(repository: whamiRepo),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/sensors',
              builder: (_, __) => SensorsScreen(repository: whamiRepo),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/packs',
              builder: (_, __) => RegionPackScreen(repository: whamiRepo),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/alerts',
              builder: (_, __) => AlertsScreen(repository: whamiRepo),
            ),
          ],
        ),
      ],
    ),

    // Settings — accessible via FAB from any screen
    GoRoute(
      path: '/settings',
      builder: (_, __) => SettingsScreen(repository: whamiRepo),
    ),
  ],
);

// ── Shell scaffold with bottom navigation ────────────────────────────────────

class _WhamiShell extends StatefulWidget {
  final StatefulNavigationShell shell;

  const _WhamiShell({required this.shell});

  @override
  State<_WhamiShell> createState() => _WhamiShellState();
}

class _WhamiShellState extends State<_WhamiShell> {
  bool _showBanner = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivityAndShowBanner();
  }

  Future<void> _checkConnectivityAndShowBanner() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.mobile) ||
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        if (mounted) {
          setState(() {
            _showBanner = true;
          });
          // Hide after 4 seconds
          Future.delayed(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _showBanner = false;
              });
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: widget.shell,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OfflineBanner(repository: whamiRepo),
              BottomNavigationBar(
                currentIndex: widget.shell.currentIndex,
                onTap: (index) => widget.shell.goBranch(
                  index,
                  initialLocation: index == widget.shell.currentIndex,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.map_outlined),
                    activeIcon: Icon(Icons.map),
                    label: 'Map',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.document_scanner_outlined),
                    activeIcon: Icon(Icons.document_scanner),
                    label: 'Scan',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.sensors_outlined),
                    activeIcon: Icon(Icons.sensors),
                    label: 'Sensors',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.inventory_2_outlined),
                    activeIcon: Icon(Icons.inventory_2),
                    label: 'Packs',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.notifications_outlined),
                    activeIcon: Icon(Icons.notifications),
                    label: 'Alerts',
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.small(
            onPressed: () => context.push('/settings'),
            backgroundColor: AppColors.headerBg,
            tooltip: 'Trust Details & Settings',
            child: const Icon(Icons.settings, color: Colors.white, size: 20),
          ),
        ),
        // Banner overlay
        // Tactical HUD Banner overlay
        AnimatedPositioned(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          top: _showBanner ? MediaQuery.of(context).padding.top + 16.0 : -150.0,
          left: 16.0,
          right: 16.0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.headerBg.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.whami.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.satellite_alt_rounded,
                          color: AppColors.whami,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SYSTEM LINK ACTIVE',
                          style: TextStyle(
                            color: AppColors.whami,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _showBanner = false),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.gps,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Downloading encrypted region packs...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
