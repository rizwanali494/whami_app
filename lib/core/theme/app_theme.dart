import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static const double minBody = 12;
  static const double body = 14;
  static const double emphasis = 16;
  static const double minTouch = 48;

  static ThemeData get theme => _build(outdoor: false);

  static ThemeData get outdoorTheme => _build(outdoor: true);

  static ThemeData _build({required bool outdoor}) {
    final bg = outdoor ? AppColors.outdoorBg : AppColors.background;
    final card = outdoor ? AppColors.outdoorCard : AppColors.cardBg;
    final text = outdoor ? AppColors.outdoorText : AppColors.textPrimary;
    final muted = outdoor ? AppColors.outdoorMuted : AppColors.textSecondary;

    return ThemeData(
      useMaterial3: true,
      brightness: outdoor ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.whami,
        brightness: outdoor ? Brightness.dark : Brightness.light,
        surface: card,
        primary: AppColors.headerBg,
      ),
      // Avoid default Inter/Roboto clustering for branded UI — use a clear
      // system sans stack that scales well outdoors.
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        color: card,
        elevation: outdoor ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.headerBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.headerBg,
        selectedItemColor: AppColors.whami,
        unselectedItemColor: Color(0xFF90A4AE),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.headerBg,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, minTouch),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
        headlineMedium: TextStyle(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        titleLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.w600,
          fontSize: emphasis,
        ),
        titleMedium: TextStyle(
          color: text,
          fontWeight: FontWeight.w600,
          fontSize: body,
        ),
        bodyLarge: TextStyle(color: text, fontSize: body, height: 1.4),
        bodyMedium: TextStyle(color: muted, fontSize: body, height: 1.4),
        bodySmall: TextStyle(color: muted, fontSize: minBody, height: 1.35),
        labelLarge: TextStyle(
          color: text,
          fontSize: body,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(
          color: muted,
          fontSize: minBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
