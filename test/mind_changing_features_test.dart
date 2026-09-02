import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/data/services/trust_fusion_engine.dart';
import 'package:WHAMI/data/services/trust_timeline_recorder.dart';
import 'package:WHAMI/data/models/trust_timeline_sample.dart';

void main() {
  final engine = TrustFusionEngine();

  GpsReading gps({
    double lat = 37.7749,
    double lng = -122.4194,
    double accuracy = 8,
    double speed = 0,
  }) {
    return GpsReading(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      altitude: 10,
      speed: speed,
      heading: 0,
      timestamp: DateTime.now(),
    );
  }

  test('GPS jump sets gnssSuspicious and memorable alert', () {
    final fused = engine.compute(
      gps: gps(lat: 37.79, lng: -122.40, speed: 1),
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: 37.7749,
      lastTrustedLng: -122.4194,
    );
    expect(fused.gnssSuspicious, isTrue);
    expect(fused.alertMessage.toLowerCase(), contains('don\'t trust this pin'));
  });

  test('locked landmark far from GPS flags spoof', () {
    final fused = engine.compute(
      gps: gps(lat: 37.80, lng: -122.45),
      magnetometer: null,
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: true,
      lastTrustedLat: 37.80,
      lastTrustedLng: -122.45,
      landmarkAnchorLat: 37.7955,
      landmarkAnchorLng: -122.3937,
      landmarkAnchorName: 'Ferry Building',
    );
    expect(fused.gnssSuspicious, isTrue);
    final landmark =
        fused.opinions.firstWhere((o) => o.sourceType == 'landmark');
    expect(landmark.description, contains('Locked to real world'));
    expect(landmark.latitude, closeTo(37.7955, 0.0001));
  });

  test('timeline recorder keeps a ring buffer', () {
    final rec = TrustTimelineRecorder();
    for (var i = 0; i < TrustTimelineRecorder.maxSamples + 20; i++) {
      rec.add(
        TrustTimelineSample(
          timestamp: DateTime.now(),
          trustScore: i % 100,
          level: 'reliable',
          latitude: 0,
          longitude: 0,
          uncertaintyM: 10,
          gnssSuspicious: false,
          witnessScores: const {'G': 90},
          brokenWitnesses: const [],
        ),
      );
    }
    expect(rec.length, TrustTimelineRecorder.maxSamples);
  });
}
