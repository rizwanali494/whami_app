import 'dart:async';
import '../../data/models/sensor_status.dart';
import 'gps_service.dart';
import 'magnetometer_service.dart';
import 'imu_service.dart';
import 'barometer_service.dart';
import 'camera_service.dart';
import 'sky_service.dart';

/// Combined snapshot of all active device sensors at a point in time
class SensorSnapshot {
  final GpsReading? gps;
  final MagnetometerReading? magnetometer;
  final ImuReading? imu;
  final BarometerReading? barometer;
  final SkyReading? sky;
  final DateTime timestamp;

  const SensorSnapshot({
    required this.gps,
    required this.magnetometer,
    required this.imu,
    required this.barometer,
    required this.sky,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Snapshot(gps: ${gps != null}, mag: ${magnetometer != null}, imu: ${imu != null}, baro: ${barometer != null})';
}

/// Central manager coordinating all hardware sensors and emitting unified snapshots
class SensorManager {
  final GpsService gpsService;
  final MagnetometerService magnetometerService;
  final ImuService imuService;
  final BarometerService barometerService;
  final CameraService cameraService;
  final SkyService skyService;

  final _controller = StreamController<SensorSnapshot>.broadcast();
  StreamSubscription? _gpsSub;
  StreamSubscription? _magSub;
  StreamSubscription? _imuSub;
  StreamSubscription? _baroSub;

  // Cached readings
  GpsReading? _lastGps;
  MagnetometerReading? _lastMag;
  ImuReading? _lastImu;
  BarometerReading? _lastBaro;
  SkyReading? _lastSky;

  Stream<SensorSnapshot> get snapshotStream => _controller.stream;

  SensorManager({
    required this.gpsService,
    required this.magnetometerService,
    required this.imuService,
    required this.barometerService,
    required this.cameraService,
    required this.skyService,
  });

  /// Initialize all hardware sensors and return a list of status mappings
  Future<void> initializeAll() async {
    await gpsService.initialize();
    await magnetometerService.initialize();
    await imuService.initialize();
    await barometerService.initialize();
    await cameraService.initialize();
  }

  /// Start all hardware subscription streams
  void startAll() {
    gpsService.startListening();
    magnetometerService.startListening();
    imuService.startListening();
    barometerService.startListening();

    _gpsSub = gpsService.stream.listen((reading) {
      _lastGps = reading;
      _updateCelestialCoords();
      _emitSnapshot();
    });

    _magSub = magnetometerService.stream.listen((reading) {
      _lastMag = reading;
      _emitSnapshot();
    });

    _imuSub = imuService.stream.listen((reading) {
      _lastImu = reading;
      _emitSnapshot();
    });

    _baroSub = barometerService.stream.listen((reading) {
      _lastBaro = reading;
      _emitSnapshot();
    });
  }

  /// Stop all hardware subscription streams
  void stopAll() {
    _gpsSub?.cancel();
    _magSub?.cancel();
    _imuSub?.cancel();
    _baroSub?.cancel();
    _gpsSub = null;
    _magSub = null;
    _imuSub = null;
    _baroSub = null;

    gpsService.stopListening();
    magnetometerService.stopListening();
    imuService.stopListening();
    barometerService.stopListening();
  }

  void _updateCelestialCoords() {
    if (_lastGps != null) {
      // Calculate live celestial alignments when GPS coordinates update
      _lastSky = skyService.calculateCelestialPositions(
        latitude: _lastGps!.latitude,
        longitude: _lastGps!.longitude,
        time: DateTime.now(),
      );
    }
  }

  void _emitSnapshot() {
    final snapshot = SensorSnapshot(
      gps: _lastGps,
      magnetometer: _lastMag,
      imu: _lastImu,
      barometer: _lastBaro,
      sky: _lastSky,
      timestamp: DateTime.now(),
    );
    _controller.add(snapshot);
  }

  /// Get status models of all sensors for UI binding
  List<SensorStatus> getSensorStatuses() {
    final now = DateTime.now();
    return [
      SensorStatus(
        id: 'gps',
        name: 'GPS Satellites',
        status: gpsService.isAvailable
            ? (_lastGps != null ? 'active' : 'available')
            : 'unavailable',
        confidence: gpsService.isAvailable
            ? (_lastGps != null
                ? (_lastGps!.accuracy < 10 ? 98 : (_lastGps!.accuracy < 30 ? 80 : 50))
                : 70)
            : 0,
        latestValue: _lastGps != null
            ? '${_lastGps!.latitude.toStringAsFixed(4)}, ${_lastGps!.longitude.toStringAsFixed(4)} (±${_lastGps!.accuracy.toStringAsFixed(1)}m)'
            : 'Waiting for fix',
        healthMessage: gpsService.statusMessage,
        iconName: 'gps_fixed',
        lastUpdated: _lastGps?.timestamp ?? now,
      ),
      SensorStatus(
        id: 'magnetometer',
        name: 'Geomagnetic Sensor',
        status: magnetometerService.isAvailable
            ? (_lastMag != null ? 'active' : 'available')
            : 'unavailable',
        confidence: magnetometerService.getConfidence(),
        latestValue: _lastMag != null
            ? '${_lastMag!.heading.toStringAsFixed(0)}° Heading (${_lastMag!.fieldStrength.toStringAsFixed(1)} µT)'
            : 'Ready',
        healthMessage: magnetometerService.statusMessage,
        iconName: 'explore',
        lastUpdated: _lastMag?.timestamp ?? now,
      ),
      SensorStatus(
        id: 'imu',
        name: 'IMU / Inertial Motion',
        status: imuService.isAvailable
            ? (_lastImu != null ? 'active' : 'available')
            : 'unavailable',
        confidence: imuService.isAvailable ? 90 : 0,
        latestValue: _lastImu != null
            ? 'Motion: ${_lastImu!.motionType.name.toUpperCase()} (Disp: ${_lastImu!.displacementX.toStringAsFixed(1)}m, ${_lastImu!.displacementY.toStringAsFixed(1)}m)'
            : 'Ready',
        healthMessage: imuService.statusMessage,
        iconName: 'navigation',
        lastUpdated: _lastImu?.timestamp ?? now,
      ),
      SensorStatus(
        id: 'barometer',
        name: 'Barometric Altimeter',
        status: barometerService.isAvailable
            ? (_lastBaro != null ? 'active' : 'available')
            : 'unavailable',
        confidence: barometerService.isAvailable ? 85 : 0,
        latestValue: _lastBaro != null
            ? '${_lastBaro!.pressure.toStringAsFixed(1)} hPa (Alt: ${_lastBaro!.estimatedAltitude.toStringAsFixed(0)}m)'
            : 'Ready',
        healthMessage: barometerService.statusMessage,
        iconName: 'height',
        lastUpdated: _lastBaro?.timestamp ?? now,
      ),
      SensorStatus(
        id: 'camera',
        name: 'Landmark Scanner',
        status: cameraService.isAvailable ? 'available' : 'unavailable',
        confidence: cameraService.isAvailable ? 75 : 0,
        latestValue: cameraService.isInitialized ? 'Live preview streaming' : 'Inactive',
        healthMessage: cameraService.statusMessage,
        iconName: 'camera_alt',
        lastUpdated: now,
      ),
      SensorStatus(
        id: 'sky',
        name: 'Celestial Alignment',
        status: _lastSky != null ? 'active' : 'available',
        confidence: _lastSky?.confidence ?? 60,
        latestValue: _lastSky != null
            ? 'Sun El: ${_lastSky!.sunElevation.toStringAsFixed(1)}°, Az: ${_lastSky!.sunAzimuth.toStringAsFixed(1)}°'
            : 'Awaiting Location',
        healthMessage: skyService.statusMessage,
        iconName: 'brightness_5',
        lastUpdated: _lastSky?.timestamp ?? now,
      ),
    ];
  }

  void dispose() {
    stopAll();
    _controller.close();
  }
}
