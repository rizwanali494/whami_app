import 'package:flutter/material.dart';
import 'app.dart';
import 'core/preferences/app_preferences.dart';
import 'navigation/whami_router.dart';

Future<void> main()
async {
  WidgetsFlutterBinding.ensureInitialized();

  await appPreferences.load();
  await bootstrapWhamiServices();

  // Initialize physical hardware sensors after services are up.
  await whamiRepo.sensors.initializeAll();

  // Start magnetometer stream immediately so readings flow from boot
  magnetometerService.startListening();
  debugPrint(
    '[main] Magnetometer stream started on launch '
    '(available: ${magnetometerService.isAvailable})',
  );

  // Start background magnetometer feed into repository opinions
  whamiRepo.startMagnetometerFeed();

  runApp(const WhamiApp());
}
