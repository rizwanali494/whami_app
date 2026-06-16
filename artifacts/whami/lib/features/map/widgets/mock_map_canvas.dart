import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class MockMapCanvas extends StatelessWidget {
  final List<PositionOpinion> opinions;

  const MockMapCanvas({super.key, required this.opinions});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: _MapPainter(opinions: opinions),
        child: Container(),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final List<PositionOpinion> opinions;

  _MapPainter({required this.opinions});

  // Base coordinate (WHAMI position center of map)
  static const double baseLat = 37.8087;
  static const double baseLng = -122.4098;

  Offset latLngToCanvas(double lat, double lng, Size size) {
    // Scale: 0.003 degrees ≈ full canvas width
    const double latRange = 0.014;
    const double lngRange = 0.020;
    final double x = (lng - (baseLng - lngRange / 2)) / lngRange * size.width;
    final double y = ((baseLat + latRange / 2) - lat) / latRange * size.height;
    return Offset(x, y);
  }

  double metersToPixels(double meters, Size size) {
    // At ~37° lat, 1 degree lng ≈ 88km, 1 degree lat ≈ 111km
    const double latRange = 0.014;
    final double pixelsPerMeter = size.height / (latRange * 111000);
    return meters * pixelsPerMeter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawWater(canvas, size);
    _drawLand(canvas, size);
    _drawHarbor(canvas, size);
    _drawRoads(canvas, size);
    _drawLandmarks(canvas, size);
    _drawUncertaintyCircles(canvas, size);
    _drawMarkers(canvas, size);
    _drawGrid(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFB8D4E8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawWater(Canvas canvas, Size size) {
    // Main water body (bay)
    final paint = Paint()..color = const Color(0xFF7BAFD4);
    final path = Path()
      ..moveTo(0, size.height * 0.35)
      ..lineTo(size.width * 0.55, size.height * 0.28)
      ..lineTo(size.width * 0.72, size.height * 0.0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawLand(Canvas canvas, Size size) {
    // Main land mass
    final paint = Paint()..color = const Color(0xFFD4E6C3);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.72, 0)
      ..lineTo(size.width * 0.55, size.height * 0.28)
      ..lineTo(size.width * 0.35, size.height * 0.38)
      ..lineTo(size.width * 0.20, size.height * 0.32)
      ..lineTo(0, size.height * 0.35)
      ..close();
    canvas.drawPath(path, paint);

    // Peninsula / wharf area
    final path2 = Path()
      ..moveTo(size.width * 0.20, size.height * 0.32)
      ..lineTo(size.width * 0.35, size.height * 0.38)
      ..lineTo(size.width * 0.30, size.height * 0.55)
      ..lineTo(size.width * 0.15, size.height * 0.58)
      ..close();
    canvas.drawPath(path2, paint);
  }

  void _drawHarbor(Canvas canvas, Size size) {
    // Harbor basin
    final paint = Paint()
      ..color = const Color(0xFF8EC6E0)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width * 0.30, size.height * 0.45)
      ..lineTo(size.width * 0.50, size.height * 0.42)
      ..lineTo(size.width * 0.55, size.height * 0.60)
      ..lineTo(size.width * 0.32, size.height * 0.63)
      ..close();
    canvas.drawPath(path, paint);

    // Piers
    final pierPaint = Paint()
      ..color = const Color(0xFF8B6914)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(size.width * 0.35, size.height * 0.46),
        Offset(size.width * 0.35, size.height * 0.62),
        pierPaint);
    canvas.drawLine(
        Offset(size.width * 0.42, size.height * 0.44),
        Offset(size.width * 0.42, size.height * 0.61),
        pierPaint);
    canvas.drawLine(
        Offset(size.width * 0.48, size.height * 0.43),
        Offset(size.width * 0.48, size.height * 0.60),
        pierPaint);
  }

  void _drawRoads(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE8C770)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Main road along shore
    canvas.drawLine(
        Offset(0, size.height * 0.30),
        Offset(size.width * 0.55, size.height * 0.25),
        paint);

    // Cross street
    canvas.drawLine(
        Offset(size.width * 0.25, 0),
        Offset(size.width * 0.28, size.height * 0.40),
        paint);

    // Harbor road
    final smallPaint = Paint()
      ..color = const Color(0xFFD4B860)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(size.width * 0.20, size.height * 0.35),
        Offset(size.width * 0.33, size.height * 0.50),
        smallPaint);
  }

  void _drawLandmarks(Canvas canvas, Size size) {
    final labels = [
      ('Harbor Tower', Offset(size.width * 0.40, size.height * 0.58)),
      ('Marina', Offset(size.width * 0.22, size.height * 0.50)),
      ('Station', Offset(size.width * 0.12, size.height * 0.22)),
      ('Depot', Offset(size.width * 0.50, size.height * 0.18)),
    ];

    for (final (label, pos) in labels) {
      // Building icon
      final buildingPaint = Paint()
        ..color = const Color(0xFF5D4037)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
          Rect.fromCenter(center: pos, width: 8, height: 8), buildingPaint);

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF3E2723),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            backgroundColor: Color(0x88FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
          canvas, pos.translate(-textPainter.width / 2, 6));
    }
  }

  void _drawUncertaintyCircles(Canvas canvas, Size size) {
    for (final op in opinions) {
      if (!op.isActive || op.uncertaintyRadius <= 0) continue;

      final center = latLngToCanvas(op.latitude, op.longitude, size);
      final radius = metersToPixels(op.uncertaintyRadius, size).clamp(8.0, size.width * 0.6);

      final paint = Paint()
        ..color = AppColors.circleForSource(op.sourceType)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);

      final borderPaint = Paint()
        ..color = AppColors.forSource(op.sourceType).withOpacity(0.5)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, radius, borderPaint);
    }
  }

  void _drawMarkers(Canvas canvas, Size size) {
    // Draw non-whami markers first, then whami on top
    final sorted = [...opinions]..sort((a, b) =>
        a.sourceType == 'whami' ? 1 : b.sourceType == 'whami' ? -1 : 0);

    for (final op in sorted) {
      if (!op.isActive) continue;

      final center = latLngToCanvas(op.latitude, op.longitude, size);
      final color = AppColors.forSource(op.sourceType);
      final isWhami = op.sourceType == 'whami';
      final radius = isWhami ? 14.0 : 11.0;

      // Shadow
      final shadowPaint = Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center.translate(1, 2), radius, shadowPaint);

      // Fill
      final fillPaint = Paint()..color = color;
      canvas.drawCircle(center, radius, fillPaint);

      // White border for whami
      if (isWhami) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(center, radius, borderPaint);
      }

      // Label text
      final textPainter = TextPainter(
        text: TextSpan(
          text: op.shortCode,
          style: TextStyle(
            color: isWhami ? Colors.black : Colors.white,
            fontSize: isWhami ? 11 : 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
          canvas,
          center.translate(
              -textPainter.width / 2, -textPainter.height / 2));
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 0.5;
    const int lines = 8;
    for (int i = 0; i <= lines; i++) {
      final x = size.width * i / lines;
      final y = size.height * i / lines;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) =>
      oldDelegate.opinions != opinions;
}
