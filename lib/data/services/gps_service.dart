import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Raw GPS reading from device
class GpsReading {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy; // meters
  final double speed; // m/s
  final double heading; // degrees
  final DateTime timestamp;

  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  @override
  String toString() =>
      'GPS(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}, '
      'acc: ${accuracy.toStringAsFixed(1)}m)';
}

/// High-level GPS readiness for UI (not the OS permission enum alone).
enum GpsAvailability {
  ready,
  waitingForFix,
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  error,
}

/// Service that streams real GPS readings from the device
class GpsService {
  StreamSubscription<Position>? _subscription;
  final _controller = StreamController<GpsReading>.broadcast();
  GpsReading? _lastReading;
  bool _isAvailable = false;
  bool _isListening = false;
  String _statusMessage = 'Initializing...';
  GpsAvailability _availability = GpsAvailability.waitingForFix;

  Stream<GpsReading> get stream => _controller.stream;
  GpsReading? get lastReading => _lastReading;
  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get statusMessage => _statusMessage;
  GpsAvailability get availability => _availability;

  /// Check permissions and mark GPS ready (does not invent a position).
  Future<bool> initialize({bool requestPermission = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _statusMessage = 'Location services disabled';
        _availability = GpsAvailability.servicesDisabled;
        _isAvailable = false;
        _lastReading = null;
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _statusMessage = 'Location permission denied';
        _availability = GpsAvailability.permissionDenied;
        _isAvailable = false;
        _lastReading = null;
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        _statusMessage = 'Location permission permanently denied';
        _availability = GpsAvailability.permissionDeniedForever;
        _isAvailable = false;
        _lastReading = null;
        return false;
      }

      _isAvailable = true;
      _availability = _lastReading == null
          ? GpsAvailability.waitingForFix
          : GpsAvailability.ready;
      _statusMessage =
          _lastReading == null ? 'Waiting for GPS fix' : 'GPS ready';
      return true;
    } catch (e) {
      _statusMessage = 'GPS initialization failed: $e';
      _availability = GpsAvailability.error;
      _isAvailable = false;
      _lastReading = null;
      return false;
    }
  }

  /// Re-check services/permission after the user changes OS settings.
  /// Restarts the stream when tracking should be live again.
  Future<bool> ensureAvailable({bool restartIfReady = true}) async {
    final ok = await initialize(requestPermission: false);
    if (ok && restartIfReady && _isListening) {
      startListening();
    }
    return ok;
  }

  /// Start streaming GPS updates
  void startListening() {
    if (!_isAvailable) return;

    _subscription?.cancel();
    _isListening = true;
    _availability = GpsAvailability.waitingForFix;
    if (_lastReading == null) {
      _statusMessage = 'Waiting for GPS fix';
    }
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // minimum 1 meter between updates
      ),
    ).listen(
      (position) {
        final reading = GpsReading(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
          timestamp: position.timestamp,
        );
        _lastReading = reading;
        _availability = GpsAvailability.ready;
        _statusMessage = 'Signal stable';
        _controller.add(reading);
      },
      onError: (e) {
        debugPrint('GPS stream error: $e');
        _statusMessage = 'GPS error: $e';
        _availability = GpsAvailability.error;
      },
    );
  }

  /// Get single position fix
  Future<GpsReading?> getCurrentPosition() async {
    if (!_isAvailable) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final reading = GpsReading(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        timestamp: position.timestamp,
      );
      _lastReading = reading;
      return reading;
    } catch (e) {
      debugPrint('GPS current position error: $e');
      return null;
    }
  }

  /// Detect if a GPS jump is physically impossible
  /// Returns distance in meters if jump detected, null otherwise
  double? detectJump(GpsReading previous, GpsReading current) {
    final timeDiff =
        current.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (timeDiff <= 0) return null;

    final distance = _haversineDistance(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );

    // Maximum plausible speed: 200 m/s (720 km/h — fast aircraft)
    final maxDistance = timeDiff * 200;
    if (distance > maxDistance && distance > 100) {
      return distance;
    }
    return null;
  }

  /// Haversine distance in meters
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  void dispose() {
    stopListening();
    _controller.close();
  }
}
