import 'package:flutter/material.dart';
import 'app.dart';
import 'core/preferences/app_preferences.dart';
import 'features/whami_air/air_preferences.dart';
import 'navigation/whami_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    appPreferences.load(),
    airPreferences.load(),
  ]);

  // Show UI immediately — sensors / permissions continue in the background.
  runApp(const WhamiApp());

  // Local tile/glyph servers (concurrent) then hardware init.
  // ignore: unawaited_futures
  () async {
    try {
      await bootstrapWhamiServices();
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
