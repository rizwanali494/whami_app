import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/sensor_card.dart';

class SensorsScreen extends StatelessWidget {
  final WhamiRepository repository;

  const SensorsScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final sensors = repository.getSensorStatuses();
        final physical = sensors
            .where((s) =>
                s.id == 'gps' ||
                s.id == 'magnetometer' ||
                s.id == 'imu' ||
                s.id == 'barometer')
            .toList();
        final derived = sensors
            .where((s) => s.id == 'camera' || s.id == 'sky')
            .toList();
        final fusion = sensors.where((s) => s.id == 'fusion').toList();
        final activeCount = sensors
            .where((s) => s.status == 'active' || s.status == 'available')
            .length;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.headerBg,
                pinned: true,
                automaticallyImplyLeading: false,
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
                      backgroundColor:
                          AppColors.trustHigh.withValues(alpha: 0.15),
                      label: Text(
                        '$activeCount/${sensors.length} Active',
                        style: const TextStyle(
                          color: AppColors.trustHigh,
                          fontSize: 12,
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
                    const _SectionLabel('Physical Sensors'),
                    ...physical.map((s) => SensorCard(sensor: s)),
                    const SizedBox(height: 8),
                    const _SectionLabel('Vision & Sky'),
                    ...derived.map((s) => SensorCard(sensor: s)),
                    const SizedBox(height: 8),
                    const _SectionLabel('Fusion Engine'),
                    ...fusion.map(
                      (s) => SensorCard(sensor: s, isFusion: true),
                    ),
                    // Clear the offline banner + nav so Barometer / Fusion
                    // cards are not obscured.
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
