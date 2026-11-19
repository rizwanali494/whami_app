import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

/// Result of snapping GPS to a real-world geometry edge.
class GeometrySnapResult {
  final double latitude;
  final double longitude;
  final double distanceM;
  final String label;
  final String kind; // coastline | runway | road | rail | canal | taxiway | trail

  const GeometrySnapResult({
    required this.latitude,
    required this.longitude,
    required this.distanceM,
    required this.label,
    required this.kind,
  });
}

/// Nearest-point snap onto bundled demo geometries (real LineStrings only).
class GeometrySnapService {
  static const supportedKinds = [
    'coastline',
    'runway',
    'road',
    'rail',
    'canal',
    'taxiway',
    'trail',
  ];

  Map<String, dynamic>? _coast;
  Map<String, dynamic>? _runway;
  Map<String, dynamic>? _routes;

  Future<void> ensureLoaded() async {
    _coast ??= jsonDecode(
          await rootBundle.loadString('assets/geometry/sf_bay_coastline.geojson'),
        )
        as Map<String, dynamic>;
    _runway ??= jsonDecode(
          await rootBundle.loadString('assets/geometry/sfo_runway_demo.geojson'),
        )
        as Map<String, dynamic>;
    _routes ??= jsonDecode(
          await rootBundle.loadString('assets/geometry/demo_routes.geojson'),
        )
        as Map<String, dynamic>;
  }

  Future<GeometrySnapResult?> snap(
    String kind,
    double lat,
    double lng, {
    double? maxDistanceM,
  }) async {
    await ensureLoaded();
    final maxM = maxDistanceM ?? _defaultMax(kind);
    switch (kind) {
      case 'coastline':
        return _snapFeatureCollection(_coast!, lat, lng, maxM, 'coastline');
      case 'runway':
        // Prefer dedicated SFO demo, then Tocumwal runway in routes.
        final a = _snapFeatureCollection(_runway!, lat, lng, maxM, 'runway');
        final b = _snapRoutes(lat, lng, maxM, kindFilter: 'runway');
        if (a == null) return b;
        if (b == null) return a;
        return a.distanceM <= b.distanceM ? a : b;
      case 'road':
      case 'rail':
      case 'canal':
      case 'taxiway':
      case 'trail':
        return _snapRoutes(lat, lng, maxM, kindFilter: kind);
      default:
        return null;
    }
  }

  Future<GeometrySnapResult?> snapCoastline(
    double lat,
    double lng, {
    double maxDistanceM = 2500,
  }) =>
      snap('coastline', lat, lng, maxDistanceM: maxDistanceM);

  Future<GeometrySnapResult?> snapRunway(
    double lat,
    double lng, {
    double maxDistanceM = 1500,
  }) =>
      snap('runway', lat, lng, maxDistanceM: maxDistanceM);

  /// Snap to nearest of all supported kinds within [maxDistanceM].
  Future<GeometrySnapResult?> snapNearest(
    double lat,
    double lng, {
    double maxDistanceM = 2500,
  }) async {
    GeometrySnapResult? best;
    for (final kind in supportedKinds) {
      final s = await snap(kind, lat, lng, maxDistanceM: maxDistanceM);
      if (s == null) continue;
      if (best == null || s.distanceM < best.distanceM) best = s;
    }
    return best;
  }

  double _defaultMax(String kind) {
    switch (kind) {
      case 'runway':
      case 'taxiway':
        return 1500;
      case 'road':
      case 'rail':
        return 1200;
      case 'trail':
      case 'canal':
        return 900;
      default:
        return 2500;
    }
  }

  GeometrySnapResult? _snapRoutes(
    double lat,
    double lng,
    double maxDistanceM, {
    required String kindFilter,
  }) {
    return _snapFeatureCollection(
      _routes!,
      lat,
      lng,
      maxDistanceM,
      kindFilter,
      requireKindProp: true,
    );
  }

  GeometrySnapResult? _snapFeatureCollection(
    Map<String, dynamic> fc,
    double lat,
    double lng,
    double maxDistanceM,
    String kind, {
    bool requireKindProp = false,
  }) {
    GeometrySnapResult? best;
    final features = fc['features'] as List<dynamic>? ?? [];
    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final propKind = props['kind'] as String?;
      if (requireKindProp && propKind != kind) continue;
      final label = (props['name'] as String?) ?? kind;
      final geom = feature['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final type = geom['type'] as String?;
      final coords = geom['coordinates'];
      final lines = <List<List<double>>>[];
      if (type == 'LineString') {
        lines.add(_asLine(coords));
      } else if (type == 'MultiLineString') {
        for (final line in coords as List) {
          lines.add(_asLine(line));
        }
      }
      for (final line in lines) {
        final snapPt = _nearestOnLine(lat, lng, line);
        if (snapPt == null) continue;
        if (snapPt.$3 > maxDistanceM) continue;
        if (best == null || snapPt.$3 < best.distanceM) {
          best = GeometrySnapResult(
            latitude: snapPt.$1,
            longitude: snapPt.$2,
            distanceM: snapPt.$3,
            label: label,
            kind: propKind ?? kind,
          );
        }
      }
    }
    return best;
  }

  List<List<double>> _asLine(dynamic coords) {
    return (coords as List)
        .map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()])
        .toList();
  }

  (double, double, double)? _nearestOnLine(
    double lat,
    double lng,
    List<List<double>> line,
  ) {
    if (line.length < 2) return null;
    var bestDist = double.infinity;
    var bestLat = lat;
    var bestLng = lng;
    for (var i = 0; i < line.length - 1; i++) {
      final aLng = line[i][0];
      final aLat = line[i][1];
      final bLng = line[i + 1][0];
      final bLat = line[i + 1][1];
      final proj = _project(lat, lng, aLat, aLng, bLat, bLng);
      final d = _haversine(lat, lng, proj.$1, proj.$2);
      if (d < bestDist) {
        bestDist = d;
        bestLat = proj.$1;
        bestLng = proj.$2;
      }
    }
    return (bestLat, bestLng, bestDist);
  }

  (double, double) _project(
    double pLat,
    double pLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final cosLat = cos(pLat * pi / 180);
    final ax = aLng * cosLat;
    final ay = aLat;
    final bx = bLng * cosLat;
    final by = bLat;
    final px = pLng * cosLat;
    final py = pLat;
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final x = ax + t * dx;
    final y = ay + t * dy;
    return (y, x / cosLat);
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
