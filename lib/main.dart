import 'package:flutter/material.dart';
import 'app.dart';
import 'navigation/whami_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize physical hardware sensors
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
