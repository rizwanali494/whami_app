import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';
import 'package:WHAMI/data/models/position_opinion.dart';
import 'package:WHAMI/features/map/widgets/compact_trust_panel.dart';

void main() {
  TrustSummary summary({
    TrustLevel level = TrustLevel.reliable,
    int score = 97,
  }) {
    return TrustSummary(
      score: score,
      level: level,
      agreeingSources: 5,
      totalSources: 6,
      uncertaintyMeters: 5,
      headline: level.label,
      subtitle: '5 of 6 sources agree · ±5 m',
      explanation: 'GPS and sensors agree closely.',
      action: 'Keep tracking.',
    );
  }

  List<PositionOpinion> opinions() => [
        const PositionOpinion(
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
        const PositionOpinion(
          id: 'imu',
          name: 'Motion',
          shortCode: 'IMU',
          sourceType: 'imu',
          confidence: 80,
          status: 'active',
          description: 'Stable',
          latitude: 37.6,
          longitude: -122.4,
          uncertaintyRadius: 12,
          colorName: 'blue',
        ),
      ];

  testWidgets('collapsed trust shows score and subtitle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactTrustPanel(
            summary: summary(),
            opinions: opinions(),
            expanded: false,
            onToggle: () {},
            onOpenVerify: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('97/100'), findsOneWidget);
    expect(find.textContaining('5 of 6 sources agree'), findsOneWidget);
  });

  testWidgets('expanded trust shows sources and verify for caution',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompactTrustPanel(
            summary: summary(level: TrustLevel.caution, score: 55),
            opinions: opinions(),
            expanded: true,
            onToggle: () {},
            onOpenVerify: () {},
          ),
        ),
      ),
    );
    expect(find.text('VERIFICATION SOURCES'), findsOneWidget);
    expect(find.text('GPS'), findsOneWidget);
    expect(find.text('Verify Position'), findsOneWidget);
  });
}
