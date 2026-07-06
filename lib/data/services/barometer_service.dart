import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Barometric pressure and calculated altitude reading
class BarometerReading {
  final double pressure; // in hPa (hectopascals) / mbar
  final double estimatedAltitude; // in meters relative to sea level
  final DateTime timestamp;

  const BarometerReading({
    required this.pressure,
    required this.estimatedAltitude,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Baro(${pressure.toStringAsFixed(1)} hPa, alt: ${estimatedAltitude.toStringAsFixed(0)}m)';
}

/// Service that streams atmospheric pressure from the device's barometer
/// Uses native method/event channels
class BarometerService {
  static const _channelName = 'com.example.whami/barometer';
  static const _methodChannel = MethodChannel('$_channelName/method');
  static const _eventChannel = EventChannel('$_channelName/stream');

  StreamSubscription<dynamic>? _subscription;
  final _controller = StreamController<BarometerReading>.broadcast();

  BarometerReading? _lastReading;
  bool _isAvailable = false;
  String _statusMessage = 'Initializing...';

  Stream<BarometerReading> get stream => _controller.stream;
  BarometerReading? get lastReading => _lastReading;
  bool get isAvailable => _isAvailable;
  String get statusMessage => _statusMessage;

  /// Initialize and check sensor availability
  Future<bool> initialize() async {
    try {
      _isAvailable = await _methodChannel.invokeMethod<bool>('isAvailable') ?? false;
      if (_isAvailable) {
        _statusMessage = 'Barometer ready';
      } else {
        _statusMessage = 'Barometer not available on device';
      }
      return _isAvailable;
    } catch (e) {
      _statusMessage = 'Barometer init failed: $e';
      _isAvailable = false;
      return false;
    }
  }

  /// Start streaming pressure updates
  void startListening() {
    if (_subscription != null) return;
    if (!_isAvailable) {
      _statusMessage = 'Barometer not available';
      return;
    }

    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic pressureVal) {
        if (pressureVal is num) {
          final pressure = pressureVal.toDouble();
          final altitude = _calculateAltitude(pressure);
          final reading = BarometerReading(
            pressure: pressure,
            estimatedAltitude: altitude,
            timestamp: DateTime.now(),
          );

          _lastReading = reading;
          _isAvailable = true;
          _statusMessage = 'Pressure stable';
          _controller.add(reading);
        }
      },
      onError: (e) {
        debugPrint('Barometer stream error: $e');
        _isAvailable = false;
        _statusMessage = 'Barometer error';
      },
    );
  }

  /// Estimate altitude from barometric pressure using standard Hypsometric Formula
  /// standard sea-level pressure is 1013.25 hPa
  double _calculateAltitude(double pressureHpa) {
    if (pressureHpa <= 0) return 0.0;
    // Standard atmosphere model
    const seaLevelPressure = 1013.25;
    return 44330.0 * (1.0 - pow(pressureHpa / seaLevelPressure, 1.0 / 5.255));
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
