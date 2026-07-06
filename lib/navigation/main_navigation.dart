import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../data/repositories/whami_repository.dart';
import 'whami_router.dart';
import '../features/map/map_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/sensors/sensors_screen.dart';
import '../features/region_packs/region_pack_screen.dart';
import '../features/alerts/alerts_screen.dart';
import '../features/settings/settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  WhamiRepository get _repository => whamiRepo;

  @override
  Widget build(BuildContext context) {
    final screens = [
      MapScreen(repository: _repository),
      ScanScreen(repository: _repository),
      SensorsScreen(repository: _repository),
      RegionPackScreen(repository: _repository),
      AlertsScreen(repository: _repository),
      SettingsScreen(repository: _repository),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex > 4 ? 4 : _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
      // FAB for quick Settings access
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => setState(() => _currentIndex = 5),
        backgroundColor: _currentIndex == 5
            ? AppColors.whami
            : AppColors.headerBg,
        tooltip: 'Trust Details & Settings',
        child: Icon(
          Icons.settings,
          color: _currentIndex == 5 ? Colors.black : Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
