import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/features/map/widgets/map_gps_hud.dart';

void main() {
  testWidgets('HUD shows dashes when GPS has no fix', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MapGpsHud(
            reading: null,
            gpsEnabled: true,
            isTracking: true,
          ),
        ),
      ),
    );
    expect(find.text('NO FIX'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('HUD shows real altitude and knots from reading', (tester) async {
    final reading = GpsReading(
      latitude: -35.81,
      longitude: 145.60,
      altitude: 120.4,
      accuracy: 4.2,
      speed: 25.7, // m/s ≈ 50 kt
      heading: 185,
      timestamp: DateTime.utc(2026, 4, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapGpsHud(reading: reading, gpsEnabled: true),
        ),
      ),
    );
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('50'), findsOneWidget); // knots
    expect(find.text('185'), findsOneWidget);
    expect(find.text('4.2'), findsOneWidget);
  });
}
