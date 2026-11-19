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
import '../data/services/wmm/wmm_service.dart';
import '../data/services/air_research_recorder.dart';
import '../data/services/magnetic_trust_model.dart';
import '../features/map/map_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/sensors/sensors_screen.dart';
import '../features/region_packs/region_pack_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/whami_air/air_screen.dart';
import '../features/whami_air/efb_advisory_screen.dart';
import '../features/whami_air/ground_station_screen.dart';
import '../features/map/trust_timeline_screen.dart';
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
final wmmService = WmmService();
final airRecorder = AirResearchRecorder();
final magCalibration = MagCalibration();
final kpService = KpIndexService();

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
  wmmService: wmmService,
  airRecorder: airRecorder,
  magCalibration: magCalibration,
  kpService: kpService,
);

/// Starts long-lived local servers after Flutter binding is ready.
Future<void> bootstrapWhamiServices() async {
  await Future.wait([
    rasterTileCacheService.start(),
    glyphServer.start(),
  ]);
  try {
    await wmmService.initialize();
  } catch (e) {
    debugPrint('[bootstrap] WMM init failed: $e');
  }
  try {
    whamiRepo.anomalyLayer = await MagneticAnomalyLayer.loadAsset(
      'assets/magnetic/demo_anomaly_corridor.json',
    );
  } catch (e) {
    debugPrint('[bootstrap] Anomaly layer load failed: $e');
  }
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
    GoRoute(
      path: '/air',
      builder: (_, __) => AirScreen(repository: whamiRepo),
    ),
    GoRoute(
      path: '/air/efb',
      builder: (_, __) => EfbAdvisoryScreen(repository: whamiRepo),
    ),
    GoRoute(
      path: '/air/ground-station',
      builder: (_, __) => GroundStationScreen(repository: whamiRepo),
    ),
    GoRoute(
      path: '/timeline',
      builder: (_, __) => TrustTimelineScreen(repository: whamiRepo),
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
          Builder(
            builder: (context) {
              final tablet =
                  MediaQuery.sizeOf(context).shortestSide >= 600;
              const cyan = Color(0xFF4FC3F7);
              const muted = Color(0xFF78909C);
              return NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: const Color(0xFF0A1628),
                  indicatorColor: cyan.withValues(alpha: 0.12),
                  overlayColor: WidgetStatePropertyAll(
                    cyan.withValues(alpha: 0.08),
                  ),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return TextStyle(
                      fontSize: tablet ? 12 : 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: 0.15,
                      color: selected ? cyan : muted,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    final selected = states.contains(WidgetState.selected);
                    return IconThemeData(
                      size: tablet ? 24 : 22,
                      color: selected ? cyan : muted,
                    );
                  }),
                ),
                child: NavigationBar(
                  height: tablet ? 72 : 64,
                  backgroundColor: const Color(0xFF0A1628),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  indicatorColor: cyan.withValues(alpha: 0.12),
                  selectedIndex: shell.currentIndex,
                  labelBehavior:
                      NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) => shell.goBranch(
                    index,
                    initialLocation: index == shell.currentIndex,
                  ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map),
                      label: 'Map',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.verified_outlined),
                      selectedIcon: Icon(Icons.verified),
                      label: 'Verify',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.sensors_outlined),
                      selectedIcon: Icon(Icons.sensors),
                      label: 'Sensors',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.offline_pin_outlined),
                      selectedIcon: Icon(Icons.offline_pin),
                      label: 'Offline',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_outlined),
                      selectedIcon: Icon(Icons.history),
                      label: 'Activity',
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
