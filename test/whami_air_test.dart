import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/wmm/wmm_service.dart';
import 'package:WHAMI/data/services/barometer_service.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/data/services/magnetometer_service.dart';
import 'package:WHAMI/data/services/trust_fusion_engine.dart';
import 'package:WHAMI/features/whami_air/air_trust.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';

void main() {
  late WmmService wmm;

  setUpAll(() {
    final cof = File('assets/wmm/WMM.COF').readAsStringSync();
    wmm = WmmService();
    wmm.loadFromCofString(cof);
  });

  test('WMM2025 matches NOAA pole test vector (2025.0, 28 km, 89N, 121W)', () {
    final f = wmm.calculate(
      latitudeDeg: 89,
      longitudeDeg: -121,
      altitudeKm: 28,
      date: DateTime.utc(2025, 1, 1),
    );
    expect(f.f, closeTo(56214.4, 1.0));
    expect(f.declination, closeTo(-99.77, 0.05));
    expect(f.h, closeTo(1504.3, 1.0));
  });

  test('WMM SF total field is plausible (~47 µT)', () {
    final f = wmm.calculate(
      latitudeDeg: 37.7749,
      longitudeDeg: -122.4194,
      altitudeKm: 0,
      date: DateTime.utc(2025, 1, 1),
    );
    expect(f.fMicroTesla, closeTo(47.5, 3.0));
  });

  test('residual scores agreement when measured F matches model', () {
    final model = wmm.calculate(
      latitudeDeg: 37.7749,
      longitudeDeg: -122.4194,
      date: DateTime.utc(2025, 1, 1),
    );
    final r = wmm.residual(
      latitudeDeg: 37.7749,
      longitudeDeg: -122.4194,
      measuredFMicroTesla: model.fMicroTesla,
      date: DateTime.utc(2025, 1, 1),
    );
    expect(r.residualMicroTesla, lessThan(0.05));
    expect(r.agreementScore, greaterThanOrEqualTo(70));
    expect(r.status, 'active');
  });

  test('baro vertical witness flags large GPS/baro altitude delta', () {
    final engine = TrustFusionEngine();
    final fused = engine.compute(
      gps: GpsReading(
        latitude: 37.77,
        longitude: -122.42,
        accuracy: 8,
        altitude: 10,
        speed: 0,
        heading: 0,
        timestamp: DateTime.now(),
      ),
      magnetometer: null,
      imu: null,
      barometer: BarometerReading(
        pressure: 900,
        estimatedAltitude: 1000,
        timestamp: DateTime.now(),
      ),
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: null,
      lastTrustedLng: null,
    );
    final baro = fused.opinions.firstWhere((o) => o.sourceType == 'baro');
    expect(baro.status, 'unstable');
    expect(fused.baroGpsAltDeltaM, greaterThan(100));
  });

  test('air trust bands map score to green/amber/red/grey', () {
    expect(
      airTrustBandFrom(
        trustScore: 80,
        level: TrustLevel.reliable,
        isTracking: true,
        activeWitnesses: 3,
      ),
      AirTrustBand.green,
    );
    expect(
      airTrustBandFrom(
        trustScore: 60,
        level: TrustLevel.caution,
        isTracking: true,
        activeWitnesses: 2,
      ),
      AirTrustBand.amber,
    );
    expect(
      airTrustBandFrom(
        trustScore: 40,
        level: TrustLevel.unreliable,
        isTracking: true,
        activeWitnesses: 2,
      ),
      AirTrustBand.red,
    );
    expect(
      airTrustBandFrom(
        trustScore: 0,
        level: TrustLevel.unknown,
        isTracking: false,
        activeWitnesses: 0,
      ),
      AirTrustBand.grey,
    );
  });

  test('WMM magnetic residual feeds fusion magnetic opinion', () {
    final engine = TrustFusionEngine();
    final fused = engine.compute(
      gps: GpsReading(
        latitude: 37.77,
        longitude: -122.42,
        accuracy: 8,
        altitude: 10,
        speed: 0,
        heading: 0,
        timestamp: DateTime.now(),
      ),
      magnetometer: MagnetometerReading(
        x: 20,
        y: 5,
        z: 40,
        heading: 90,
        fieldStrength: 47.5,
        timestamp: DateTime.now(),
      ),
      imu: null,
      barometer: null,
      sky: null,
      landmarkMatch: null,
      magneticMatch: null,
      seamapMatch: null,
      hasOfflineData: false,
      lastTrustedLat: null,
      lastTrustedLng: null,
      wmmResidualUt: 1.2,
      wmmAgreementScore: 88,
      wmmStatus: 'active',
      wmmDescription: 'WMM agrees: residual 1.2 µT',
    );
    final mag = fused.opinions.firstWhere((o) => o.sourceType == 'magnetic');
    expect(mag.confidence, 88);
    expect(mag.description, contains('WMM'));
    expect(fused.magneticAgreement, 88);
  });
}
