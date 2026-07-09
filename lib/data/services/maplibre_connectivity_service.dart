import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Forces MapLibre Native's internal connectivity check to always report
/// "connected", so its core HTTP client never refuses requests to our local
/// loopback tile server based on the device's real (possibly offline) OS
/// connectivity state. See MainActivity.kt for the native side — this is
/// only reachable via a custom platform channel, not the maplibre_gl
/// plugin's own Dart API.
class MapLibreConnectivityService {
  static const _channel = MethodChannel(
    'com.example.whami/maplibre_connectivity',
  );

  /// Call this whenever a MapLibreMap view is (re)created. The engine-startup
  /// call in MainActivity.kt is not sufficient on its own — MapLibre Native
  /// (re-)activates its own connectivity receiver when a map view
  /// initializes, which can re-query the real OS state and clobber the
  /// earlier override.
  static Future<void> forceConnected() async {
    try {
      await _channel.invokeMethod('forceConnected');
    } catch (e) {
      debugPrint('[MapLibreConnectivityService] forceConnected failed: $e');
    }
  }
}
