import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/theme/whami_aviation.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';
import 'package:WHAMI/core/widgets/whami_chrome.dart';
import 'package:WHAMI/data/models/position_opinion.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/features/map/widgets/compact_trust_panel.dart';
import 'package:WHAMI/features/map/widgets/map_gps_hud.dart';

/// Visual gallery goldens for the premium aviation chrome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShot(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF1B2838),
          body: Center(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('map HUD unavailable golden', (tester) async {
    await pumpShot(
      tester,
      const Padding(
        padding: EdgeInsets.all(16),
        child: MapGpsHud(
          reading: null,
          gpsEnabled: true,
          isTracking: true,
        ),
      ),
    );
    await expectLater(
      find.byType(MapGpsHud),
      matchesGoldenFile('goldens/map_hud_no_fix.png'),
    );
  });

  testWidgets('map HUD live golden', (tester) async {
    final reading = GpsReading(
      latitude: -35.81,
      longitude: 145.60,
      altitude: 320,
      accuracy: 5,
      speed: 41.16, // ~80 kt
      heading: 220,
      timestamp: DateTime.utc(2026, 4, 12),
    );
    await pumpShot(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: MapGpsHud(
          reading: reading,
          gpsEnabled: true,
          isTracking: true,
        ),
      ),
    );
    await expectLater(
      find.byType(MapGpsHud),
      matchesGoldenFile('goldens/map_hud_live.png'),
    );
  });

  testWidgets('glass offline card golden', (tester) async {
    await pumpShot(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: WhamiGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('OFFLINE', style: WhamiAviation.overline(color: WhamiAviation.cyan)),
              const SizedBox(height: 6),
              const Text(
                'Demo landmarks · streets use cached basemap',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(WhamiGlassCard),
      matchesGoldenFile('goldens/offline_glass_card.png'),
    );
  });

  testWidgets('tablet HUD width golden', (tester) async {
    await pumpShot(
      tester,
      const Padding(
        padding: EdgeInsets.all(24),
        child: MapGpsHud(
          reading: null,
          gpsEnabled: false,
          isTracking: true,
        ),
      ),
      size: const Size(1024, 768),
    );
    await expectLater(
      find.byType(MapGpsHud),
      matchesGoldenFile('goldens/map_hud_tablet.png'),
    );
  });

  testWidgets('compact trust panel golden', (tester) async {
    await pumpShot(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: CompactTrustPanel(
          summary: const TrustSummary(
            level: TrustLevel.reliable,
            score: 97,
            agreeingSources: 5,
            totalSources: 6,
            uncertaintyMeters: 5,
            headline: 'Position reliable',
            subtitle: '5 of 6 sources agree · ±5 m',
            explanation: 'Most sensors agree.',
            action: 'Keep tracking.',
          ),
          opinions: const [
            PositionOpinion(
              id: 'gps',
              name: 'GPS',
              shortCode: 'GPS',
              sourceType: 'gps',
              confidence: 92,
              status: 'active',
              description: 'Good fix',
              latitude: 37.6,
              longitude: -122.4,
              uncertaintyRadius: 5,
              colorName: 'green',
            ),
          ],
          expanded: false,
          onToggle: () {},
          onOpenVerify: () {},
        ),
      ),
    );
    await expectLater(
      find.byType(CompactTrustPanel),
      matchesGoldenFile('goldens/compact_trust_panel.png'),
    );
  });
}
