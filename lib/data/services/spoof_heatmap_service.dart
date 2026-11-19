import 'dart:math' as math;

import '../models/trust_timeline_sample.dart';

/// A coarse GNSS-risk cell for map overlay / situational awareness.
class SpoofHeatCell {
  final double latitude;
  final double longitude;
  final double radiusM;
  final double intensity; // 0..1
  final int hitCount;
  final String label;

  const SpoofHeatCell({
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.intensity,
    required this.hitCount,
    required this.label,
  });
}

/// Builds spoof risk cells from local timeline + optional demo corridor.
class SpoofHeatmapService {
  /// Demo corridor near Tocumwal / Riverina for offline demos.
  static const List<SpoofHeatCell> demoCells = [
    SpoofHeatCell(
      latitude: -35.8117,
      longitude: 145.6083,
      radiusM: 1800,
      intensity: 0.55,
      hitCount: 3,
      label: 'Demo · aerodrome GNSS noise',
    ),
    SpoofHeatCell(
      latitude: -35.84,
      longitude: 145.65,
      radiusM: 2200,
      intensity: 0.35,
      hitCount: 1,
      label: 'Demo · corridor caution',
    ),
  ];

  List<SpoofHeatCell> build({
    required List<TrustTimelineSample> samples,
    bool includeDemo = true,
  }) {
    final buckets = <String, _Bucket>{};

    for (final s in samples) {
      if (!s.gnssSuspicious) continue;
      final lat = s.gpsClaimLatitude ?? s.latitude;
      final lng = s.gpsClaimLongitude ?? s.longitude;
      final key = '${(lat * 200).round()}_${(lng * 200).round()}';
      final b = buckets.putIfAbsent(
        key,
        () => _Bucket(lat: lat, lng: lng),
      );
      b.count += 1;
      b.maxLie = math.max(b.maxLie, s.lieDistanceM ?? 0);
    }

    final cells = <SpoofHeatCell>[];
    for (final b in buckets.values) {
      final intensity = (0.25 + (b.count * 0.12) + (b.maxLie / 5000))
          .clamp(0.2, 1.0)
          .toDouble();
      cells.add(
        SpoofHeatCell(
          latitude: b.lat,
          longitude: b.lng,
          radiusM: (600 + b.maxLie * 0.15).clamp(500, 4000).toDouble(),
          intensity: intensity,
          hitCount: b.count,
          label: 'Local spoof hits · ${b.count}',
        ),
      );
    }

    if (includeDemo && cells.isEmpty) {
      cells.addAll(demoCells);
    } else if (includeDemo) {
      // Keep demo faint so real hits dominate.
      cells.addAll(
        demoCells.map(
          (c) => SpoofHeatCell(
            latitude: c.latitude,
            longitude: c.longitude,
            radiusM: c.radiusM,
            intensity: c.intensity * 0.45,
            hitCount: c.hitCount,
            label: c.label,
          ),
        ),
      );
    }

    cells.sort((a, b) => b.intensity.compareTo(a.intensity));
    return cells.take(24).toList();
  }
}

class _Bucket {
  double lat;
  double lng;
  int count = 0;
  double maxLie = 0;
  _Bucket({required this.lat, required this.lng});
}
