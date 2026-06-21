import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Raw magnetometer reading
class MagnetometerReading {
  final double x; // µT
  final double y; // µT
  final double z; // µT
  final double heading; // degrees (0-360)
  final double fieldStrength; // total µT
  final DateTime timestamp;

  const MagnetometerReading({
    required this.x,
    required this.y,
    required this.z,
    required this.heading,
    required this.fieldStrength,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Mag(heading: ${heading.toStringAsFixed(0)}°, ${fieldStrength.toStringAsFixed(1)} µT)';
}

/// Service that streams real magnetometer readings from the device
class MagnetometerService {
  StreamSubscription? _subscription;
  final _controller = StreamController<MagnetometerReading>.broadcast();
  MagnetometerReading? _lastReading;
  bool _isAvailable = false;
  String _statusMessage = 'Initializing...';

  // Baseline for interference detection
  double _baselineStrength = 0;
  final List<double> _recentStrengths = [];
  static const int _baselineWindowSize = 20;

  Stream<MagnetometerReading> get stream => _controller.stream;
  MagnetometerReading? get lastReading => _lastReading;
  bool get isAvailable => _isAvailable;
  String get statusMessage => _statusMessage;
  double get baselineStrength => _baselineStrength;

  /// Initialize and check availability
  Future<bool> initialize() async {
    try {
      // Test if magnetometer events are available
      final completer = Completer<bool>();
      StreamSubscription? testSub;

      testSub = magnetometerEventStream().listen(
        (event) {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
          testSub?.cancel();
        },
        onError: (e) {
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          testSub?.cancel();
        },
      );

      // Timeout after 2 seconds
      final available = await completer.future
          .timeout(const Duration(seconds: 2), onTimeout: () {
        testSub?.cancel();
        return false;
      });

      _isAvailable = available;
      _statusMessage = available ? 'Magnetometer ready' : 'Not available';
      return available;
    } catch (e) {
      _statusMessage = 'Magnetometer init failed: $e';
      _isAvailable = false;
      return false;
    }
  }

  /// Start streaming magnetometer updates
  void startListening() {
    if (!_isAvailable) return;

    _subscription = magnetometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen(
      (event) {
        final fieldStrength = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );

        // Compute heading from x,y
        var heading = atan2(event.y, event.x) * 180 / pi;
        if (heading < 0) heading += 360;

        // Update baseline
        _recentStrengths.add(fieldStrength);
        if (_recentStrengths.length > _baselineWindowSize) {
          _recentStrengths.removeAt(0);
        }
        if (_recentStrengths.length >= 5) {
          _baselineStrength = _recentStrengths.reduce((a, b) => a + b) /
              _recentStrengths.length;
        }

        final reading = MagnetometerReading(
          x: event.x,
          y: event.y,
          z: event.z,
          heading: heading,
          fieldStrength: fieldStrength,
          timestamp: DateTime.now(),
        );

        _lastReading = reading;
        _statusMessage = 'Field stable';
        _controller.add(reading);
      },
      onError: (e) {
        debugPrint('Magnetometer stream error: $e');
        _statusMessage = 'Magnetometer error';
      },
    );
  }

  /// Detect magnetic interference
  /// Returns true if current field is significantly different from baseline
  bool detectInterference() {
    if (_lastReading == null || _baselineStrength == 0) return false;
    final deviation =
        (_lastReading!.fieldStrength - _baselineStrength).abs() /
            _baselineStrength;
    return deviation > 0.5; // 50% deviation from baseline
  }

  /// Get confidence based on field stability
  int getConfidence() {
    if (!_isAvailable || _lastReading == null) return 0;
    if (detectInterference()) return 18;
    if (_recentStrengths.length < 5) return 50;

    // Calculate variance
    final mean = _baselineStrength;
    final variance = _recentStrengths
            .map((s) => (s - mean) * (s - mean))
            .reduce((a, b) => a + b) /
        _recentStrengths.length;
    final stdDev = sqrt(variance);

    // Lower std dev = more stable = higher confidence
    if (stdDev < 1) return 92;
    if (stdDev < 3) return 78;
    if (stdDev < 5) return 65;
    if (stdDev < 10) return 45;
    return 25;
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopListening();
    _controller.close();
  }
}
