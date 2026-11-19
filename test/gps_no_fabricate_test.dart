import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/trust_fusion_engine.dart';

void main() {
  test('fusion does not invent SF when no GPS, trail, or landmark', () {
    final engine = TrustFusionEngine();
    final fused = engine.compute(
      gps: null,
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: null,
      lastTrustedLng: null,
      gpsUnavailableReason: 'Location services disabled',
    );

    expect(fused.hasValidFix, isFalse);
    expect(fused.confidence, 0);
    // Must not be the old SF Bay fabrication.
    expect(fused.latitude, isNot(closeTo(37.8087, 0.01)));
    expect(fused.longitude, isNot(closeTo(-122.4098, 0.01)));
    final gpsOpinion = fused.opinions.firstWhere((o) => o.sourceType == 'gps');
    expect(gpsOpinion.status, 'unavailable');
    expect(gpsOpinion.description, 'Location services disabled');
  });

  test('fusion keeps last trusted fix when GPS is gone', () {
    final engine = TrustFusionEngine();
    final fused = engine.compute(
      gps: null,
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: -35.81,
      lastTrustedLng: 145.60,
      gpsUnavailableReason: 'Waiting for GPS fix',
    );

    expect(fused.hasValidFix, isTrue);
    expect(fused.latitude, closeTo(-35.81, 0.001));
    expect(fused.longitude, closeTo(145.60, 0.001));
  });
}
