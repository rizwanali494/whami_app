import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/models/flight_plan.dart';
import 'package:WHAMI/data/services/route_progress.dart';

void main() {
  final plan = FlightPlan(
    id: 't',
    name: 'Test',
    updatedAt: DateTime.utc(2026, 1, 1),
    waypoints: const [
      FlightWaypoint(id: 'a', name: 'A', latitude: -35.81, longitude: 145.60),
      FlightWaypoint(id: 'b', name: 'B', latitude: -35.64, longitude: 145.58),
    ],
  );

  test('on-track point has small cross-track error', () {
    // Midpoint roughly on the segment.
    final midLat = (-35.81 + -35.64) / 2;
    final midLng = (145.60 + 145.58) / 2;
    final p = RouteProgress.fromPlan(plan: plan, lat: midLat, lng: midLng);
    expect(p, isNotNull);
    expect(p!.crossTrackM.abs(), lessThan(200));
    expect(p.fractionAlong, greaterThan(0.3));
    expect(p.fractionAlong, lessThan(0.7));
    expect(p.nextWaypointName, 'B');
  });

  test('offset point reports left/right of track', () {
    final midLat = (-35.81 + -35.64) / 2;
    final midLng = (145.60 + 145.58) / 2;
    // Nudge east (~1 km).
    final p = RouteProgress.fromPlan(
      plan: plan,
      lat: midLat,
      lng: midLng + 0.012,
    );
    expect(p, isNotNull);
    expect(p!.crossTrackM.abs(), greaterThan(500));
    expect(p.crossTrackLabel.toLowerCase(), contains('of track'));
    expect(p.toNextLabel.toLowerCase(), contains('to b'));
  });

  test('single waypoint plan has no progress', () {
    final one = plan.copyWith(waypoints: [plan.waypoints.first]);
    expect(
      RouteProgress.fromPlan(plan: one, lat: -35.81, lng: 145.60),
      isNull,
    );
  });
}
