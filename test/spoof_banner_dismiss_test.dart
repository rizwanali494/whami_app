import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/features/map/widgets/spoof_alarm_banner.dart';
import 'package:WHAMI/features/map/widgets/witness_crossfire_panel.dart';
import 'package:WHAMI/data/services/witness_crossfire.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';
import 'package:WHAMI/data/models/position_opinion.dart';
import 'package:WHAMI/data/models/region_pack.dart';

void main() {
  testWidgets('spoof banner shows X and Dismiss actions', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpoofAlarmBanner(
            message: 'Jump 5047 m without matching speed.',
            onVerify: () {},
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsWidgets);

    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('sensor crossfire panel shows close and Dismiss', (tester) async {
    var dismissed = false;
    const cf = WitnessCrossfire(
      visible: true,
      headline: '1 agree. Outliers: G.',
      trustedLat: 1,
      trustedLng: 1,
      witnesses: [],
      agreeingIds: [],
      outlierIds: ['gps'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WitnessCrossfirePanel(
            crossfire: cf,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('SENSOR CROSSFIRE'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  test('trust summary is not Reliable when GPS is suspicious', () {
    final summary = TrustSummary.fromOpinions(
      trustScore: 96,
      isTracking: true,
      gnssSuspicious: true,
      opinions: [
        PositionOpinion(
          id: 'gps',
          name: 'GPS',
          shortCode: 'G',
          sourceType: 'gps',
          colorName: 'blue',
          latitude: 1,
          longitude: 1,
          confidence: 95,
          uncertaintyRadius: 12,
          status: 'unstable',
          description: 'jumped',
        ),
        PositionOpinion(
          id: 'mag',
          name: 'Magnetic',
          shortCode: 'M',
          sourceType: 'magnetic',
          colorName: 'purple',
          latitude: 1,
          longitude: 1,
          confidence: 93,
          uncertaintyRadius: 20,
          status: 'active',
          description: 'ok',
        ),
      ],
    );
    expect(summary.level, isNot(TrustLevel.reliable));
    expect(summary.score, lessThanOrEqualTo(60));
    expect(summary.subtitle.toLowerCase(), contains('gps flagged'));
  });

  test('AU catalog entry formats as Demo size', () {
    final pack = RegionPack.fromCatalogEntry({
      'id': 'aus_victoria_nsw',
      'name': 'Victoria / NSW Riverina',
      'country': 'Australia',
      'packType': 'Aviation',
      'bundled': true,
      'sizeBytes': 32768,
      'trustScore': 85,
    });
    expect(pack.id, 'aus_victoria_nsw');
    expect(pack.size, 'Demo');
    expect(pack.status, 'available');
  });
}
