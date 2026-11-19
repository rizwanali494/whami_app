import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/models/flight_plan.dart';

void main() {
  test('flight plan serializes and restores waypoints', () {
    final plan = FlightPlan(
      id: 'p1',
      name: 'Tocumwal hop',
      updatedAt: DateTime.utc(2026, 4, 12),
      waypoints: const [
        FlightWaypoint(
          id: 'a',
          name: 'YTOC',
          latitude: -35.8117,
          longitude: 145.6083,
        ),
        FlightWaypoint(
          id: 'b',
          name: '052FinAP',
          latitude: -35.644,
          longitude: 145.578,
        ),
      ],
    );

    final restored = FlightPlan.fromJsonString(plan.toJsonString());
    expect(restored.id, 'p1');
    expect(restored.waypoints, hasLength(2));
    expect(restored.waypoints[1].name, '052FinAP');
    expect(restored.hasRoute, isTrue);
    expect(restored.totalLengthM, greaterThan(1000));
    expect(restored.totalLengthM, lessThan(50000));
  });

  test('empty plan has no route length', () {
    final plan = FlightPlan.empty(name: 'Scratch');
    expect(plan.isEmpty, isTrue);
    expect(plan.hasRoute, isFalse);
    expect(plan.totalLengthM, 0);
  });

  test('travel route empty starts with Travel route name prefix', () {
    final plan = FlightPlan.empty();
    expect(plan.name, startsWith('Travel route'));
    expect(plan.isEmpty, isTrue);
  });

  test('pins ahead connect into a route once two or more', () {
    var plan = FlightPlan.empty();
    plan = plan.copyWith(
      waypoints: [
        const FlightWaypoint(
          id: '1',
          name: 'Origin',
          latitude: -35.81,
          longitude: 145.60,
        ),
        const FlightWaypoint(
          id: '2',
          name: 'WP02',
          latitude: -35.70,
          longitude: 145.55,
        ),
        const FlightWaypoint(
          id: '3',
          name: 'Destination',
          latitude: -35.64,
          longitude: 145.58,
        ),
      ],
    );
    expect(plan.waypoints, hasLength(3));
    expect(plan.hasRoute, isTrue);
    expect(plan.legLengthsM, hasLength(2));
    expect(plan.totalLengthNm, greaterThan(0));
    expect(
      FlightPlan.formatCoord(-35.81, 145.60),
      contains("S"),
    );
    expect(
      FlightPlan.formatCoord(-35.81, 145.60),
      contains("E"),
    );
  });
}
