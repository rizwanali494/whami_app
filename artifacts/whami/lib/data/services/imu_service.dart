import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Type of motion detected by IMU
enum MotionType { stationary, walking, vehicle, boat, unknown }

/// Raw IMU (inertial measurement unit) reading containing accelerometer & gyroscope data
class ImuReading {
  final double accelX; // m/s²
  final double accelY; // m/s²
  final double accelZ; // m/s²
  final double gyroX; // rad/s
  final double gyroY; // rad/s
  final double gyroZ; // rad/s
  final MotionType motionType;
  final double displacementX; // dead-reckoned displacement in meters since tracking started
  final double displacementY; // dead-reckoned displacement in meters since tracking started
  final DateTime timestamp;

  const ImuReading({
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.motionType,
    required this.displacementX,
    required this.displacementY,
    required this.timestamp,
  });

  @override
  String toString() =>
      'IMU(motion: ${motionType.name}, disp: (${displacementX.toStringAsFixed(1)}m, ${displacementY.toStringAsFixed(1)}m))';
}

/// Service that streams accelerometer & gyroscope readings to perform dead-reckoning & motion classification
class ImuService {
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  final _controller = StreamController<ImuReading>.broadcast();

  // Internal state
  ImuReading? _lastReading;
  bool _isAvailable = false;
  String _statusMessage = 'Initializing...';

  // Sensor reading caches
  double _lastAx = 0;
  double _lastAy = 0;
  double _lastAz = 0;
  double _lastGx = 0;
  double _lastGy = 0;
  double _lastGz = 0;

  // Window for motion classification
  final List<double> _accelMagnitudes = [];
  final List<double> _gyroMagnitudes = [];
  static const int _windowSize = 25; // ~5 seconds of data at 5Hz

  // Dead reckoning state
  double _velocityX = 0.0;
  double _velocityY = 0.0;
  double _displacementX = 0.0;
  double _displacementY = 0.0;
  DateTime? _lastStepTime;
  int _stepCount = 0;

  Stream<ImuReading> get stream => _controller.stream;
  ImuReading? get lastReading => _lastReading;
  bool get isAvailable => _isAvailable;
  String get statusMessage => _statusMessage;
  int get stepCount => _stepCount;

  /// Initialize and check accelerometer + gyroscope availability
  Future<bool> initialize() async {
    try {
      final accelCompleter = Completer<bool>();
      StreamSubscription? testSub;
      testSub = accelerometerEventStream().listen(
        (event) {
          if (!accelCompleter.isCompleted) accelCompleter.complete(true);
          testSub?.cancel();
        },
        onError: (e) {
          if (!accelCompleter.isCompleted) accelCompleter.complete(false);
          testSub?.cancel();
        },
      );

      final available = await accelCompleter.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          testSub?.cancel();
          return false;
        },
      );

      _isAvailable = available;
      _statusMessage = available ? 'IMU ready' : 'IMU sensors not available';
      return available;
    } catch (e) {
      _statusMessage = 'IMU init failed: $e';
      _isAvailable = false;
      return false;
    }
  }

  /// Reset dead-reckoning displacement values
  void resetDeadReckoning() {
    _velocityX = 0;
    _velocityY = 0;
    _displacementX = 0;
    _displacementY = 0;
    _stepCount = 0;
    _lastStepTime = null;
  }

  /// Start listening to accelerometer and gyroscope streams
  void startListening() {
    if (!_isAvailable) return;

    final sampling = const Duration(milliseconds: 200); // 5Hz

    _accelSub = accelerometerEventStream(samplingPeriod: sampling).listen(
      (event) {
        _lastAx = event.x;
        _lastAy = event.y;
        _lastAz = event.z;
        _onSensorTick();
      },
      onError: (e) {
        debugPrint('Accelerometer error: $e');
        _statusMessage = 'IMU stream error';
      },
    );

    _gyroSub = gyroscopeEventStream(samplingPeriod: sampling).listen(
      (event) {
        _lastGx = event.x;
        _lastGy = event.y;
        _lastGz = event.z;
      },
      onError: (e) {
        debugPrint('Gyroscope error: $e');
      },
    );
  }

  void _onSensorTick() {
    final now = DateTime.now();
    final magnitude = sqrt(_lastAx * _lastAx + _lastAy * _lastAy + _lastAz * _lastAz);
    final gyroMag = sqrt(_lastGx * _lastGx + _lastGy * _lastGy + _lastGz * _lastGz);

    // Save history for classification
    _accelMagnitudes.add(magnitude);
    _gyroMagnitudes.add(gyroMag);
    if (_accelMagnitudes.length > _windowSize) _accelMagnitudes.removeAt(0);
    if (_gyroMagnitudes.length > _windowSize) _gyroMagnitudes.removeAt(0);

    // Motion classification
    final motion = _classifyMotion();

    // Dead-reckoning integration (velocity and position updates)
    final dt = _lastReading != null
        ? now.difference(_lastReading!.timestamp).inMilliseconds / 1000.0
        : 0.0;

    if (dt > 0 && dt < 1.0) {
      // Remove gravity component roughly (assuming vertical Z is gravity on table)
      // For walking/sea state, we use simple step/tilt heuristics:
      if (motion == MotionType.walking) {
        // Step-based dead-reckoning (typically ~0.8m per step)
        // Detect step peaks in acceleration
        if (magnitude > 12.0) {
          if (_lastStepTime == null || now.difference(_lastStepTime!).inMilliseconds > 400) {
            _stepCount++;
            _lastStepTime = now;
            // Accumulate forward displacement in a pseudo-yaw direction
            // Since we don't have true attitude estimation, we increment relative X,Y
            _displacementX += 0.8 * cos(_lastGx);
            _displacementY += 0.8 * sin(_lastGx);
          }
        }
      } else if (motion == MotionType.vehicle || motion == MotionType.boat) {
        // Simple linear acceleration double integration with high dampening (leak)
        final rawAx = _lastAx;
        final rawAy = _lastAy;

        // Apply a high-pass filter / deadband to ignore sensor noise/gravity tilt
        final axFiltered = rawAx.abs() > 0.3 ? rawAx : 0.0;
        final ayFiltered = rawAy.abs() > 0.3 ? rawAy : 0.0;

        _velocityX = (_velocityX + axFiltered * dt) * 0.95; // 5% dampening leak to avoid infinite drift
        _velocityY = (_velocityY + ayFiltered * dt) * 0.95;

        _displacementX += _velocityX * dt;
        _displacementY += _velocityY * dt;
      }
    }

    final reading = ImuReading(
      accelX: _lastAx,
      accelY: _lastAy,
      accelZ: _lastAz,
      gyroX: _lastGx,
      gyroY: _lastGy,
      gyroZ: _lastGz,
      motionType: motion,
      displacementX: _displacementX,
      displacementY: _displacementY,
      timestamp: now,
    );

    _lastReading = reading;
    _statusMessage = 'IMU streaming live';
    _controller.add(reading);
  }

  MotionType _classifyMotion() {
    if (_accelMagnitudes.length < 5) return MotionType.unknown;

    // Calculate variance of acceleration
    final mean = _accelMagnitudes.reduce((a, b) => a + b) / _accelMagnitudes.length;
    final variance = _accelMagnitudes
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        _accelMagnitudes.length;
    final stdDev = sqrt(variance);

    // Calculate mean gyroscope magnitude
    final meanGyro = _gyroMagnitudes.isEmpty
        ? 0.0
        : _gyroMagnitudes.reduce((a, b) => a + b) / _gyroMagnitudes.length;

    // Threshold classification
    if (stdDev < 0.15 && meanGyro < 0.05) {
      return MotionType.stationary;
    } else if (stdDev >= 0.15 && stdDev < 1.2 && meanGyro < 0.3) {
      // Slow rhythmic pitching/rolling can indicate boat motion
      if (meanGyro > 0.08) {
        return MotionType.boat;
      }
      return MotionType.vehicle;
    } else if (stdDev >= 1.2) {
      return MotionType.walking;
    }

    return MotionType.unknown;
  }

  void stopListening() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
  }

  void dispose() {
    stopListening();
    _controller.close();
  }
}
