import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

class WhamiApp extends StatelessWidget {
  const WhamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WHAMI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
