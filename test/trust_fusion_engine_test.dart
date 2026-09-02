import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/data/services/magnetometer_service.dart';
import 'package:WHAMI/data/services/position_matcher.dart';
import 'package:WHAMI/data/services/sky_service.dart';
import 'package:WHAMI/data/services/trust_fusion_engine.dart';

void main() {
  final engine = TrustFusionEngine();

  GpsReading gps({
    double lat = 37.7749,
    double lng = -122.4194,
    double accuracy = 8,
  }) {
    return GpsReading(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      altitude: 10,
      speed: 0,
      heading: 0,
      timestamp: DateTime.now(),
    );
  }

  MagnetometerReading mag() {
    return MagnetometerReading(
      x: 20,
      y: 5,
      z: 40,
      heading: 90,
      fieldStrength: 45,
      timestamp: DateTime.now(),
    );
  }

  test('does not invent random jitter on landmark or sky opinions', () {
    final a = engine.compute(
      gps: gps(),
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: SkyReading(
        sunAzimuth: 180,
        sunElevation: 40,
        moonAzimuth: 90,
        moonElevation: 20,
        confidence: 70,
        timestamp: DateTime.now(),
      ),
      landmarkMatch: const LandmarkMatch(
        name: 'Ferry Building',
        distance: 40,
        confidence: 0.9,
      ),
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: true,
      lastTrustedLat: null,
      lastTrustedLng: null,
    );

    final landmark = a.opinions.firstWhere((o) => o.sourceType == 'landmark');
    final sky = a.opinions.firstWhere((o) => o.sourceType == 'sextant');
    expect(landmark.latitude, 37.7749);
    expect(landmark.longitude, -122.4194);
    expect(sky.latitude, 37.7749);
    expect(sky.longitude, -122.4194);
  });

  test('magnetometer without GPS is verify-only and does not pull to 0,0', () {
    final fused = engine.compute(
      gps: null,
      magnetometer: mag(),
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: 37.8,
      lastTrustedLng: -122.4,
    );

    final magnetic = fused.opinions.firstWhere((o) => o.sourceType == 'magnetic');
    expect(magnetic.status, 'verify');
    // Fused position must stay near last trusted — not Gulf of Guinea (0,0).
    expect(fused.latitude, closeTo(37.8, 0.05));
    expect(fused.longitude, closeTo(-122.4, 0.05));
    expect(fused.latitude.abs() + fused.longitude.abs(), greaterThan(1));
  });

  test('landmark anchor supplies position when GPS is missing', () {
    final fused = engine.compute(
      gps: null,
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: true,
      lastTrustedLat: null,
      lastTrustedLng: null,
      landmarkAnchorLat: 37.7955,
      landmarkAnchorLng: -122.3937,
      landmarkAnchorName: 'Ferry Building',
    );

    expect(fused.latitude, closeTo(37.7955, 0.0001));
    expect(fused.longitude, closeTo(-122.3937, 0.0001));
    final landmark = fused.opinions.firstWhere((o) => o.sourceType == 'landmark');
    expect(landmark.status, 'active');
    expect(landmark.description, contains('Locked to real world'));
  });
}
