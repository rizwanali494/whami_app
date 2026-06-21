import 'package:flutter/material.dart';
import 'app.dart';
import 'navigation/whami_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize physical hardware sensors
  await whamiRepo.sensors.initializeAll();

  runApp(const WhamiApp());
}
