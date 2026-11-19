import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/models/position_opinion.dart';
import 'package:WHAMI/data/services/witness_crossfire.dart';

void main() {
  PositionOpinion gps({
    double lat = 37.80,
    double lng = -122.45,
    String status = 'unstable',
    int confidence = 30,
  }) {
    return PositionOpinion(
      id: 'gps',
      name: 'GPS / GNSS',
      shortCode: 'G',
      sourceType: 'gps',
      latitude: lat,
      longitude: lng,
      confidence: confidence,
      uncertaintyRadius: 50,
      colorName: 'blue',
      status: status,
      description: 'GPS jumped — spoofing suspected.',
    );
  }

  PositionOpinion landmark() {
    return PositionOpinion(
      id: 'landmark',
      name: 'Landmark',
      shortCode: 'L',
      sourceType: 'landmark',
      latitude: 37.7955,
      longitude: -122.3937,
      confidence: 90,
      uncertaintyRadius: 40,
      colorName: 'black',
      status: 'active',
      description: 'Locked to real world: Ferry Building',
    );
  }

  PositionOpinion imu() {
    return PositionOpinion(
      id: 'imu',
      name: 'Motion',
      shortCode: 'I',
      sourceType: 'imu',
      latitude: 37.7956,
      longitude: -122.3938,
      confidence: 78,
      uncertaintyRadius: 25,
      colorName: 'purple',
      status: 'active',
      description: 'Device steady',
    );
  }

  test('crossfire names GPS as outlier when sensors agree', () {
    final cf = WitnessCrossfire.fromOpinions(
      opinions: [gps(), landmark(), imu()],
      trustedLat: 37.7955,
      trustedLng: -122.3937,
      trustScore: 35,
      gnssSuspicious: true,
      isTracking: true,
    );
    expect(cf.visible, isTrue);
    expect(cf.headline.toLowerCase(), contains('gps'));
    expect(cf.headline.toLowerCase(), contains('outlier'));
    expect(cf.headline.toLowerCase(), contains('sensor'));
    expect(cf.outlierIds, contains('gps'));
    expect(cf.agreeingIds, isNotEmpty);
  });

  test('crossfire hidden when not tracking or score healthy', () {
    final off = WitnessCrossfire.fromOpinions(
      opinions: [gps(), landmark()],
      trustedLat: 37.7955,
      trustedLng: -122.3937,
      trustScore: 35,
      gnssSuspicious: true,
      isTracking: false,
    );
    expect(off.visible, isFalse);

    final healthy = WitnessCrossfire.fromOpinions(
      opinions: [gps(status: 'active', confidence: 90, lat: 37.7955, lng: -122.3937), landmark()],
      trustedLat: 37.7955,
      trustedLng: -122.3937,
      trustScore: 88,
      gnssSuspicious: false,
      isTracking: true,
    );
    expect(healthy.visible, isFalse);
  });

  test('tap why uses opinion description', () {
    final cf = WitnessCrossfire.fromOpinions(
      opinions: [gps(), landmark()],
      trustedLat: 37.7955,
      trustedLng: -122.3937,
      trustScore: 40,
      gnssSuspicious: true,
      isTracking: true,
    );
    final g = cf.witnesses.firstWhere((w) => w.id == 'gps');
    expect(g.why.toLowerCase(), contains('spoof'));
  });
}
