import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/services/barometer_service.dart';
import 'package:WHAMI/data/services/camera_service.dart';
import 'package:WHAMI/data/services/gps_service.dart';
import 'package:WHAMI/data/services/imu_service.dart';
import 'package:WHAMI/data/services/magnetometer_service.dart';
import 'package:WHAMI/data/services/sensor_manager.dart';
import 'package:WHAMI/data/services/sky_service.dart';

void main() {
  SensorManager buildManager() {
    return SensorManager(
      gpsService: GpsService(),
      magnetometerService: MagnetometerService(),
      imuService: ImuService(),
      barometerService: BarometerService(),
      cameraService: CameraService(),
      skyService: SkyService(),
    );
  }

  test('pauseGps and resumeGps do not throw when GPS never started', () {
    final sm = buildManager();
    sm.pauseGps();
    sm.resumeGps();
    sm.pauseGps();
  });

  test('stopAllKeepMagnetometer clears GPS without throwing', () {
    final sm = buildManager();
    sm.stopAllKeepMagnetometer();
  });
}
