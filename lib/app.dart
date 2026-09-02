import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/preferences/app_preferences.dart';
import 'features/whami_air/air_preferences.dart';
import 'core/theme/app_theme.dart';
import 'navigation/whami_router.dart';

class WhamiApp extends StatelessWidget {
  const WhamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppPreferences>.value(value: appPreferences),
        ChangeNotifierProvider<AirPreferences>.value(value: airPreferences),
      ],
      child: Consumer<AppPreferences>(
        builder: (context, prefs, _) {
          return MaterialApp.router(
            title: 'WHAMI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.theme,
            darkTheme: AppTheme.outdoorTheme,
            themeMode:
                prefs.outdoorMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: whamiRouter,
            builder: (context, child) {
              // Respect system text scaling up to 200% for outdoor readability.
              final mq = MediaQuery.of(context);
              final clamped = mq.textScaler.clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 2.0,
              );
              return MediaQuery(
                data: mq.copyWith(textScaler: clamped),
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
