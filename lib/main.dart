import 'package:flutter/material.dart';
import 'app.dart';
import 'core/preferences/app_preferences.dart';
import 'data/services/maplibre_connectivity_service.dart';
import 'features/whami_air/air_preferences.dart';
import 'navigation/whami_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    appPreferences.load(),
    airPreferences.load(),
  ]);

  // Tile/glyph loopback servers MUST be up before the map builds its style
  // JSON — otherwise rasterCacheUrl is empty, MapLibre hits the CDN without
  // OSM's required User-Agent, and the map stays blank teal.
  await bootstrapWhamiServices();
  await MapLibreConnectivityService.forceConnected();

  runApp(const WhamiApp());

  // Sensors / permissions continue in the background after first frame.
  // ignore: unawaited_futures
  () async {
    try {
      await whamiRepo.sensors.initializeAll();
      magnetometerService.startListening();
      debugPrint(
        '[main] Magnetometer stream started '
        '(available: ${magnetometerService.isAvailable})',
      );
      whamiRepo.startMagnetometerFeed();
    } catch (e) {
      debugPrint('[main] Background sensor bootstrap failed: $e');
    }
  }();
}
