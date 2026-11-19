import 'dart:math';

import '../models/flight_plan.dart';

/// Position of WHAMI's trusted fix relative to the active task line.
class RouteProgress {
  final double alongTrackM;
  final double crossTrackM;
  final double distanceToNextM;
  final int nextWaypointIndex;
  final String nextWaypointName;
  final double totalRouteM;
  final double fractionAlong;
  final double nearestLat;
  final double nearestLng;

  const RouteProgress({
    required this.alongTrackM,
    required this.crossTrackM,
    required this.distanceToNextM,
    required this.nextWaypointIndex,
    required this.nextWaypointName,
    required this.totalRouteM,
    required this.fractionAlong,
    required this.nearestLat,
    required this.nearestLng,
  });

  /// Positive cross-track = right of track (looking along route).
  String get crossTrackLabel {
    final abs = crossTrackM.abs();
    final side = crossTrackM >= 0 ? 'right' : 'left';
    if (abs >= 1000) {
      return '${(abs / 1000).toStringAsFixed(1)} km $side of track';
    }
    return '${abs.round()} m $side of track';
  }

  String get toNextLabel {
    if (distanceToNextM >= 1000) {
      return '${(distanceToNextM / 1000).toStringAsFixed(1)} km to $nextWaypointName';
    }
    return '${distanceToNextM.round()} m to $nextWaypointName';
  }

  /// Project [lat]/[lng] onto the polyline of [plan].
  static RouteProgress? fromPlan({
    required FlightPlan plan,
    required double lat,
    required double lng,
  }) {
    if (!plan.hasRoute) return null;
    final wps = plan.waypoints;

    var bestDist = double.infinity;
    var bestAlong = 0.0;
    var bestCross = 0.0;
    var bestSeg = 0;
    var bestT = 0.0;
    var bestNearLat = wps.first.latitude;
    var bestNearLng = wps.first.longitude;
    var prefix = 0.0;

    for (var i = 0; i < wps.length - 1; i++) {
      final a = wps[i];
      final b = wps[i + 1];
      final segLen = FlightPlan.haversineM(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      if (segLen < 1) continue;

      final proj = _projectOntoSegmentMeters(
        lat,
        lng,
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      final d = FlightPlan.haversineM(lat, lng, proj.lat, proj.lng);
      if (d < bestDist) {
        bestDist = d;
        bestAlong = prefix + proj.t * segLen;
        bestCross = proj.crossM;
        bestSeg = i;
        bestT = proj.t;
        bestNearLat = proj.lat;
        bestNearLng = proj.lng;
      }
      prefix += segLen;
    }

    final total = plan.totalLengthM;
    var nextIndex = bestSeg + 1;
    if (bestT >= 0.999 && nextIndex < wps.length - 1) {
      nextIndex += 1;
    }
    nextIndex = nextIndex.clamp(1, wps.length - 1);
    final next = wps[nextIndex];
    final toNext =
        FlightPlan.haversineM(lat, lng, next.latitude, next.longitude);

    return RouteProgress(
      alongTrackM: bestAlong.clamp(0, total),
      crossTrackM: bestCross,
      distanceToNextM: toNext,
      nextWaypointIndex: nextIndex,
      nextWaypointName: next.name,
      totalRouteM: total,
      fractionAlong: total > 0 ? (bestAlong / total).clamp(0.0, 1.0) : 0,
      nearestLat: bestNearLat,
      nearestLng: bestNearLng,
    );
  }

  /// Local meters projection onto segment A→B. Cross > 0 = right of track.
  static ({double lat, double lng, double t, double crossM})
      _projectOntoSegmentMeters(
    double pLat,
    double pLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final midLatRad = ((aLat + bLat) / 2) * pi / 180;
    final mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(midLatRad);

    final ax = 0.0;
    final ay = 0.0;
    final bx = (bLng - aLng) * mPerDegLng;
    final by = (bLat - aLat) * mPerDegLat;
    final px = (pLng - aLng) * mPerDegLng;
    final py = (pLat - aLat) * mPerDegLat;

    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = 0.0;
    if (len2 > 1e-6) {
      t = ((px - ax) * dx + (py - ay) * dy) / len2;
      t = t.clamp(0.0, 1.0);
    }
    final nx = ax + t * dx;
    final ny = ay + t * dy;
    final nearLat = aLat + ny / mPerDegLat;
    final nearLng =
        mPerDegLng.abs() > 1e-9 ? aLng + nx / mPerDegLng : aLng;

    final len = sqrt(len2);
    final crossM = len > 1e-6 ? (dx * (py - ay) - dy * (px - ax)) / len : 0.0;

    return (lat: nearLat, lng: nearLng, t: t, crossM: crossM);
  }
}
