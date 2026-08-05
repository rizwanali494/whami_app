import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';
import 'package:WHAMI/data/models/position_opinion.dart';

void main() {
  test('TrustSummary maps high consensus to Reliable', () {
    final opinions = [
      PositionOpinion(
        id: 'gps',
        name: 'GPS',
        shortCode: 'G',
        sourceType: 'gps',
        colorName: 'blue',
        latitude: 1,
        longitude: 1,
        confidence: 90,
        uncertaintyRadius: 12,
        status: 'active',
        description: 'ok',
      ),
      PositionOpinion(
        id: 'landmark',
        name: 'Landmark',
        shortCode: 'L',
        sourceType: 'landmark',
        colorName: 'black',
        latitude: 1,
        longitude: 1,
        confidence: 88,
        uncertaintyRadius: 15,
        status: 'active',
        description: 'ok',
      ),
    ];

    final summary = TrustSummary.fromOpinions(
      trustScore: 82,
      opinions: opinions,
      isTracking: true,
    );

    expect(summary.level, TrustLevel.reliable);
    expect(summary.headline, contains('reliable'));
    expect(summary.subtitle, contains('sources agree'));
  });

  test('TrustSummary uses Checking when idle with no witnesses', () {
    final summary = TrustSummary.fromOpinions(
      trustScore: 75,
      opinions: const [],
      isTracking: false,
    );
    expect(summary.level, TrustLevel.unknown);
  });
}
