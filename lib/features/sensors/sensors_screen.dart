import 'package:flutter/material.dart';
import '../../core/theme/whami_aviation.dart';
import '../../core/widgets/whami_chrome.dart';
import '../../data/repositories/whami_repository.dart';
import '../../data/services/gps_service.dart';
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
        final gps = repository.liveGpsReading;
        final pad = WhamiLayout.pagePad(context);

        return Scaffold(
          backgroundColor: WhamiAviation.lightWash,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: WhamiAviation.navy,
                pinned: true,
                automaticallyImplyLeading: false,
                expandedHeight: 72,
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SENSORS',
                      style: TextStyle(
                        color: WhamiAviation.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      'Live hardware status',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                actions: [
                  Padding(
                    padding: EdgeInsets.only(right: pad),
                    child: Center(
                      child: WhamiStatusPill(
                        label: '$activeCount/${sensors.length} live',
                        color: WhamiAviation.success,
                      ),
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
                      child: _GpsDetailCard(
                        reading: gps,
                        gpsEnabled: repository.gpsEnabled,
                        statusMessage: repository.gpsStatusMessage,
                        onRetry: () => repository.retryLocation(),
                      ),
                    ),
                    WhamiSectionLabel('Physical Sensors', light: true),
                    ...physical.map((s) => SensorCard(sensor: s)),
                    WhamiSectionLabel('Vision & Sky', light: true),
                    ...derived.map((s) => SensorCard(sensor: s)),
                    WhamiSectionLabel('Fusion Engine', light: true),
                    ...fusion.map(
                      (s) => SensorCard(sensor: s, isFusion: true),
                    ),
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

class _GpsDetailCard extends StatelessWidget {
  final GpsReading? reading;
  final bool gpsEnabled;
  final String statusMessage;
  final VoidCallback onRetry;

  const _GpsDetailCard({
    required this.reading,
    required this.gpsEnabled,
    required this.statusMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final live = gpsEnabled && reading != null;
    return WhamiGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                live ? Icons.satellite_alt : Icons.gps_off,
                color: live ? WhamiAviation.cyan : WhamiAviation.amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                live ? 'GNSS FIX' : 'GNSS',
                style: WhamiAviation.overline(color: WhamiAviation.cyan),
              ),
              const Spacer(),
              if (!live)
                TextButton(
                  onPressed: onRetry,
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      color: WhamiAviation.cyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (!live) ...[
            const SizedBox(height: 6),
            Text(
              !gpsEnabled ? 'GPS paused — sensors only' : statusMessage,
              style: WhamiAviation.body(),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                WhamiMetricCell(
                  label: 'ALT',
                  value: reading!.altitude.isFinite
                      ? '${reading!.altitude.round()}'
                      : '—',
                  unit: 'm',
                ),
                WhamiMetricCell(
                  label: 'GS',
                  value: () {
                    final kt = reading!.speed * 1.943844;
                    if (!reading!.speed.isFinite || reading!.speed < 0) {
                      return '—';
                    }
                    return kt < 10
                        ? kt.toStringAsFixed(1)
                        : kt.round().toString();
                  }(),
                  unit: 'kt',
                ),
                WhamiMetricCell(
                  label: 'HDG',
                  value: (reading!.speed >= 0.5 && reading!.heading.isFinite)
                      ? '${reading!.heading.round() % 360}'
                      : '—',
                  unit: '°',
                ),
                WhamiMetricCell(
                  label: 'ACC',
                  value: reading!.accuracy.isFinite && reading!.accuracy > 0
                      ? (reading!.accuracy < 10
                          ? reading!.accuracy.toStringAsFixed(1)
                          : '${reading!.accuracy.round()}')
                      : '—',
                  unit: 'm',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
