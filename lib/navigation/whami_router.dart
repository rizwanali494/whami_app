import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/repositories/whami_repository.dart';
import '../data/repositories/region_repository.dart';
import '../data/repositories/landmark_repository.dart';
import '../data/repositories/map_repository.dart';
import '../data/services/gps_service.dart';
import '../data/services/magnetometer_service.dart';
import '../data/services/imu_service.dart';
import '../data/services/barometer_service.dart';
import '../data/services/camera_service.dart';
import '../data/services/sky_service.dart';
import '../data/services/sensor_manager.dart';
import '../data/services/region_pack_storage.dart';
import '../data/services/download_engine.dart';
import '../data/services/region_engine.dart';
import '../data/services/raster_tile_cache_service.dart';
import '../data/services/glyph_server.dart';
import '../data/services/landmark_database.dart';
import '../data/services/landmark_engine.dart';
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
import '../features/onboarding/onboarding_screen.dart';
import '../core/constants/app_colors.dart';
import '../core/preferences/app_preferences.dart';
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

final rasterTileCacheService = RasterTileCacheService();
final glyphServer = GlyphServer();

final storage = RegionPackStorage();
final downloadEngine = DownloadEngine(storage: storage);
final landmarkDatabase = LandmarkDatabase();
final regionEngine =
    RegionEngine(storage: storage, landmarkDatabase: landmarkDatabase);
final landmarkEngine =
    LandmarkEngine(regionEngine: regionEngine, db: landmarkDatabase);

final regionRepo =
    RegionRepository(regionEngine: regionEngine, downloadEngine: downloadEngine);
final landmarkRepo = LandmarkRepository(landmarkEngine: landmarkEngine);
final mapRepo = MapRepository();

final matcher = PositionMatcher();
final fusionEngine = TrustFusionEngine();
final eventLog = TrustEventLog();

final whamiRepo = WhamiRepository(
  sensors: sensorManager,
  matcher: matcher,
  fusionEngine: fusionEngine,
  eventLog: eventLog,
  regionRepository: regionRepo,
  landmarkRepository: landmarkRepo,
  mapRepository: mapRepo,
  rasterTileCacheService: rasterTileCacheService,
  glyphServer: glyphServer,
);

/// Starts long-lived local servers after Flutter binding is ready.
Future<void> bootstrapWhamiServices() async {
  await Future.wait([
    rasterTileCacheService.start(),
    glyphServer.start(),
  ]);
}

final whamiRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: appPreferences,
  redirect: (context, state) {
    if (!appPreferences.isReady) return null;
    final loc = state.matchedLocation;
    if (!appPreferences.onboardingSeen &&
        loc != '/onboarding' &&
        loc != '/') {
      return '/onboarding';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
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
              path: '/verify',
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
              builder: (_, __) =>
                  RegionPackScreen(repository: whamiRepo),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/activity',
              builder: (_, __) => AlertsScreen(repository: whamiRepo),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => SettingsScreen(repository: whamiRepo),
    ),
    // Legacy path redirects
    GoRoute(path: '/scan', redirect: (_, __) => '/verify'),
    GoRoute(path: '/alerts', redirect: (_, __) => '/activity'),
  ],
);

class _WhamiShell extends StatelessWidget {
  final StatefulNavigationShell shell;

  const _WhamiShell({required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OfflineBanner(repository: whamiRepo),
          NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: AppColors.headerBg,
              indicatorColor: AppColors.whami.withValues(alpha: 0.22),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.whami : const Color(0xFF90A4AE),
                );
              }),
            ),
            child: NavigationBar(
              height: 68,
              backgroundColor: AppColors.headerBg,
              indicatorColor: AppColors.whami.withValues(alpha: 0.22),
              selectedIndex: shell.currentIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) => shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.map_outlined, color: Color(0xFF90A4AE)),
                  selectedIcon: Icon(Icons.map, color: AppColors.whami),
                  label: 'Map',
                ),
                NavigationDestination(
                  icon: Icon(Icons.verified_outlined, color: Color(0xFF90A4AE)),
                  selectedIcon: Icon(Icons.verified, color: AppColors.whami),
                  label: 'Verify',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sensors_outlined, color: Color(0xFF90A4AE)),
                  selectedIcon: Icon(Icons.sensors, color: AppColors.whami),
                  label: 'Sensors',
                ),
                NavigationDestination(
                  icon:
                      Icon(Icons.offline_pin_outlined, color: Color(0xFF90A4AE)),
                  selectedIcon: Icon(Icons.offline_pin, color: AppColors.whami),
                  label: 'Offline',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history, color: Color(0xFF90A4AE)),
                  selectedIcon: Icon(Icons.history, color: AppColors.whami),
                  label: 'Activity',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
