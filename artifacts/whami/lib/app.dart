import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'navigation/whami_router.dart';

class WhamiApp extends StatelessWidget {
  const WhamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WHAMI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      routerConfig: whamiRouter,
      builder: (context, child) {
        return Container(
          color: const Color(0xFF0D1117),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: ClipRect(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
