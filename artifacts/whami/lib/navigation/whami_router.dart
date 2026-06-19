import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/repositories/whami_mock_repository.dart';
import '../features/map/map_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/sensors/sensors_screen.dart';
import '../features/region_packs/region_pack_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/offline_banner.dart';

/// Single shared repository — replace with a proper DI provider for production.
final whamiRepo = WhamiMockRepository();

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
            GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
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
          BottomNavigationBar(
            currentIndex: shell.currentIndex,
            onTap: (index) => shell.goBranch(
              index,
              initialLocation: index == shell.currentIndex,
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
    );
  }
}
