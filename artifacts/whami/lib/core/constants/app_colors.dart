import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF2F4F7);
  static const Color headerBg = Color(0xFF0A1628);
  static const Color cardBg = Color(0xFFFFFFFF);

  // Source colors
  static const Color whami = Color(0xFFFFC107);    // Amber / Yellow
  static const Color gps = Color(0xFF2196F3);       // Blue
  static const Color landmark = Color(0xFF212121);  // Black
  static const Color magnetic = Color(0xFFE53935);  // Red
  static const Color sextant = Color(0xFF43A047);   // Green
  static const Color imu = Color(0xFF8E24AA);       // Purple

  // Uncertainty circle colors (with alpha)
  static const Color whamiCircle = Color(0x33FFC107);
  static const Color gpsCircle = Color(0x332196F3);
  static const Color landmarkCircle = Color(0x33212121);
  static const Color magneticCircle = Color(0x33E53935);
  static const Color sextantCircle = Color(0x3343A047);
  static const Color imuCircle = Color(0x338E24AA);

  // Trust score gradient
  static const Color trustHigh = Color(0xFF43A047);
  static const Color trustMedium = Color(0xFFFFC107);
  static const Color trustLow = Color(0xFFE53935);

  // UI
  static const Color textPrimary = Color(0xFF0A1628);
  static const Color textSecondary = Color(0xFF546E7A);
  static const Color divider = Color(0xFFECEFF1);
  static const Color alertWarning = Color(0xFFFFF3E0);
  static const Color alertWarningBorder = Color(0xFFFFB300);
  static const Color alertCritical = Color(0xFFFFEBEE);
  static const Color alertCriticalBorder = Color(0xFFE53935);
  static const Color alertInfo = Color(0xFFE3F2FD);
  static const Color alertInfoBorder = Color(0xFF2196F3);

  static Color forSource(String sourceType) {
    switch (sourceType) {
      case 'whami': return whami;
      case 'gps': return gps;
      case 'landmark': return landmark;
      case 'magnetic': return magnetic;
      case 'sextant': return sextant;
      case 'imu': return imu;
      default: return textSecondary;
    }
  }

  static Color circleForSource(String sourceType) {
    switch (sourceType) {
      case 'whami': return whamiCircle;
      case 'gps': return gpsCircle;
      case 'landmark': return landmarkCircle;
      case 'magnetic': return magneticCircle;
      case 'sextant': return sextantCircle;
      case 'imu': return imuCircle;
      default: return Colors.grey.withOpacity(0.2);
    }
  }

  static Color forTrust(int trust) {
    if (trust >= 75) return trustHigh;
    if (trust >= 55) return trustMedium;
    return trustLow;
  }
}
