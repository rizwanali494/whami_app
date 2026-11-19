import 'package:flutter/material.dart';

/// Premium aviation chrome tokens for WHAMI.
/// Dark navy / charcoal surfaces, restrained cyan accents, outdoor-readable contrast.
class WhamiAviation {
  WhamiAviation._();

  // Surfaces
  static const Color navy = Color(0xFF0A1628);
  static const Color charcoal = Color(0xFF122033);
  static const Color panel = Color(0xFF152238);
  static const Color panelElevated = Color(0xFF1A2B42);
  static const Color hairline = Color(0x22FFFFFF);
  static const Color hairlineStrong = Color(0x33FFFFFF);

  // Accents (restrained aviation cyan + amber WHAMI)
  static const Color cyan = Color(0xFF4FC3F7);
  static const Color cyanDim = Color(0xFF0288D1);
  static const Color amber = Color(0xFFFFC107);
  static const Color success = Color(0xFF43A047);
  static const Color caution = Color(0xFFB28704);
  static const Color danger = Color(0xFFE53935);

  // Text
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFFB0BEC5);
  static const Color textMuted = Color(0xFF78909C);

  // Light outdoor panels (trust sheet / readable daylight)
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightInk = Color(0xFF0A1628);
  static const Color lightMuted = Color(0xFF546E7A);
  static const Color lightWash = Color(0xFFF5F7FA);
  static const Color lightBorder = Color(0xFFE2E8EE);

  static TextStyle overline({Color color = textSecondary}) => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: color,
        height: 1.1,
      );

  static TextStyle title({Color color = textPrimary}) => TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: color,
        height: 1.15,
      );

  static TextStyle body({Color color = textSecondary}) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.35,
      );

  static TextStyle metricValue({Color color = textPrimary}) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.05,
      );

  static TextStyle metricUnit({Color color = textMuted}) => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: color,
      );

  static BoxDecoration glassPanel({BorderRadius? radius}) => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [charcoal, navy],
        ),
        borderRadius: radius ?? BorderRadius.circular(16),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration lightCard({BorderRadius? radius}) => BoxDecoration(
        color: lightSurface,
        borderRadius: radius ?? BorderRadius.circular(16),
        border: Border.all(color: lightBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      );
}

/// Phone vs Tripltek / tablet spacing and control sizes.
class WhamiLayout {
  WhamiLayout._();

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= 600;

  static double mapFabSize(BuildContext context) =>
      isTablet(context) ? 58 : 52;

  static double mapFabIcon(BuildContext context) =>
      isTablet(context) ? 24 : 22;

  static double pagePad(BuildContext context) =>
      isTablet(context) ? 24 : 16;

  static double contentMaxWidth(BuildContext context) =>
      isTablet(context) ? 720 : double.infinity;

  static double navBarHeight(BuildContext context) =>
      isTablet(context) ? 76 : 68;

  static EdgeInsets pageInsets(BuildContext context) {
    final p = pagePad(context);
    return EdgeInsets.fromLTRB(p, 12, p, 16);
  }
}
