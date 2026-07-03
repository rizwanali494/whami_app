import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/sensor_card.dart';

class SensorsScreen extends StatelessWidget {
  final WhamiRepository repository;

  const SensorsScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    final sensors = repository.getSensorStatuses();
    final nonFusion = sensors.where((s) => s.id != 'fusion').toList();
    final fusion = sensors.where((s) => s.id == 'fusion').toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            title: const Text(
              'Sensor Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  backgroundColor: AppColors.trustHigh.withValues(alpha: 0.15),
                  label: Text(
                    '${nonFusion.where((s) => s.status == 'active' || s.status == 'available').length}/${nonFusion.length} Active',
                    style: TextStyle(
                      color: AppColors.trustHigh,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    'Physical Sensors',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...nonFusion.map((s) => SensorCard(sensor: s)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Fusion Engine',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                ...fusion.map((s) => SensorCard(sensor: s, isFusion: true)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
