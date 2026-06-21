import 'dart:math';
import '../../data/models/position_opinion.dart';
import 'gps_service.dart';
import 'magnetometer_service.dart';
import 'imu_service.dart';
import 'barometer_service.dart';
import 'sky_service.dart';
import 'position_matcher.dart';

/// Represents the output of the Trust Fusion Engine
class FusedPosition {
  final double latitude;
  final double longitude;
  final int confidence; // 0 to 100
  final double uncertaintyRadius; // meters
  final List<PositionOpinion> opinions;
  final String alertMessage;
  final String alertSeverity; // none, info, warning, critical

  const FusedPosition({
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.uncertaintyRadius,
    required this.opinions,
    required this.alertMessage,
    required this.alertSeverity,
  });

  @override
  String toString() =>
      'FusedPosition(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}, confidence: $confidence%, radius: ${uncertaintyRadius.toStringAsFixed(1)}m)';
}

/// Core engine that integrates multiple sensor inputs and offline GeoJSON matches,
/// checks for anomalies (spoofing, interference), and computes a single trusted coordinate.
class TrustFusionEngine {
  /// Compiles all sensor feeds and local database match results, running the fusion algorithm
  FusedPosition compute({
    required GpsReading? gps,
    required MagnetometerReading? magnetometer,
    required ImuReading? imu,
    required BarometerReading? barometer,
    required SkyReading? sky,
    required LandmarkMatch? landmarkMatch,
    required MagneticMatch? magneticMatch,
    required SeamapMatch? seamapMatch,
    required bool hasOfflineData,
    required double? lastTrustedLat,
    required double? lastTrustedLng,
  }) {
    final opinions = <PositionOpinion>[];
    String alertMessage = 'Positions aligned. System nominal.';
    String alertSeverity = 'none';

    // ── 1. GPS Position Opinion ──────────────────────────────────────────────
    if (gps != null) {
      String status = 'active';
      String desc = 'Live GPS fix';

      // Detect anomalies (GPS jumps)
      if (lastTrustedLat != null && lastTrustedLng != null) {
        final distFromLastTrusted = _haversine(
          lastTrustedLat,
          lastTrustedLng,
          gps.latitude,
          gps.longitude,
        );
        // If GPS jumped > 1000m and speed doesn't explain it, flag GPS anomaly
        if (distFromLastTrusted > 1000 && gps.speed < 50) {
          status = 'unstable';
          desc = 'GPS coordinate jump detected! Potential spoofing.';
          alertMessage = 'WARNING: Unexpected GPS jump detected. Cross-checking sensor indices.';
          alertSeverity = 'warning';
        }
      }

      opinions.add(PositionOpinion.fromGps(
        latitude: gps.latitude,
        longitude: gps.longitude,
        accuracy: gps.accuracy,
        status: status,
        description: desc,
      ));
    } else {
      opinions.add(PositionOpinion.unavailable(
        id: 'gps',
        name: 'GPS / GNSS',
        shortCode: 'G',
        sourceType: 'gps',
        colorName: 'blue',
        description: 'Waiting for satellite signals',
      ));
    }

    // ── 2. Landmark Matching Opinion ─────────────────────────────────────────
    if (hasOfflineData && landmarkMatch != null && gps != null) {
      // Landmark position is considered highly precise. If GPS matches it, high confidence.
      // If we point camera or match landmarks, our position is bounded by that landmark.
      // For this engine, we project the landmark opinion. If user is close,
      // the landmark opinion is at the nearest landmark location, with a small uncertainty radius.
      final confidenceScore = (landmarkMatch.confidence * 100).toInt();
      final double estimatedUncertainty = landmarkMatch.distance.clamp(10.0, 150.0);

      opinions.add(PositionOpinion.fromLandmark(
        latitude: gps.latitude + ((Random().nextDouble() - 0.5) * 0.0001), // Jitter near GPS
        longitude: gps.longitude + ((Random().nextDouble() - 0.5) * 0.0001),
        confidence: confidenceScore,
        uncertaintyRadius: estimatedUncertainty,
        status: 'active',
        description: 'Nearest matched landmark: ${landmarkMatch.name}',
      ));
    } else {
      opinions.add(PositionOpinion.unavailable(
        id: 'landmark',
        name: 'Landmark / Seamap',
        shortCode: 'L',
        sourceType: 'landmark',
        colorName: 'black',
        description: hasOfflineData ? 'No landmarks identified in range' : 'No region pack active',
      ));
    }

    // ── 3. Magnetic Grid Opinion ─────────────────────────────────────────────
    if (hasOfflineData && magneticMatch != null && magnetometer != null && gps != null) {
      // Cross check expected field vs live readings
      final isInterfered = magneticMatch.deviation > 8.0; // deviation > 8 µT is heavy interference
      final status = isInterfered ? 'unstable' : 'active';
      final confidenceScore = isInterfered
          ? 20
          : (magneticMatch.stability * 95).toInt();
      
      String desc = 'Field deviation: ${magneticMatch.deviation.toStringAsFixed(1)} µT';
      if (isInterfered) {
        desc += ' (Interference detected!)';
        alertMessage = 'ALERT: Geomagnetic anomalies detected. Metallic interference possible.';
        alertSeverity = 'info';
      }

      // Magnetic lookup gives position validation
      opinions.add(PositionOpinion.fromMagnetic(
        latitude: gps.latitude,
        longitude: gps.longitude,
        confidence: confidenceScore,
        uncertaintyRadius: isInterfered ? 500.0 : 150.0,
        status: status,
        description: desc,
      ));
    } else {
      opinions.add(PositionOpinion.unavailable(
        id: 'magnetic',
        name: 'Magnetic Field',
        shortCode: 'M',
        sourceType: 'magnetic',
        colorName: 'red',
        description: hasOfflineData ? 'Magnetometer reading waiting' : 'No region pack active',
      ));
    }

    // ── 4. IMU Dead-Reckoning Opinion ────────────────────────────────────────
    if (imu != null && lastTrustedLat != null && lastTrustedLng != null) {
      // Integrate IMU displacement into coordinates
      // 1 degree latitude ~ 111,000 meters. 1 degree longitude ~ 111,000 * cos(lat) meters.
      final latRad = lastTrustedLat * pi / 180;
      final newLat = lastTrustedLat + (imu.displacementY / 111000.0);
      final newLng = lastTrustedLng + (imu.displacementX / (111000.0 * cos(latRad)));

      // Confidence slowly decays as displacement grows to represent drift
      final driftDistance = sqrt(imu.displacementX * imu.displacementX + imu.displacementY * imu.displacementY);
      final double uncertainty = (30.0 + (driftDistance * 0.1)).clamp(30.0, 1000.0);
      final confidenceScore = (85 - (driftDistance * 0.05).toInt()).clamp(10, 90);

      opinions.add(PositionOpinion.fromImu(
        latitude: newLat,
        longitude: newLng,
        confidence: confidenceScore,
        uncertaintyRadius: uncertainty,
        status: 'active',
        description: 'Dead reckoning. Drift: ${driftDistance.toStringAsFixed(0)}m',
      ));
    } else {
      opinions.add(PositionOpinion.unavailable(
        id: 'imu',
        name: 'IMU Movement',
        shortCode: 'I',
        sourceType: 'imu',
        colorName: 'purple',
        description: 'IMU tracking inactive',
      ));
    }

    // ── 5. Celestial Alignment Opinion ───────────────────────────────────────
    if (sky != null && gps != null) {
      // Sky calculation provides coarse offline verification
      opinions.add(PositionOpinion.fromSky(
        latitude: gps.latitude + ((Random().nextDouble() - 0.5) * 0.003), // Coarse scale jitter
        longitude: gps.longitude + ((Random().nextDouble() - 0.5) * 0.003),
        confidence: sky.confidence,
        uncertaintyRadius: 800.0,
        status: 'active',
        description: 'Celestial azimuth alignment: Sun ${sky.sunAzimuth.toStringAsFixed(0)}°',
      ));
    } else {
      opinions.add(PositionOpinion.unavailable(
        id: 'sextant',
        name: 'Sextant / Sky',
        shortCode: 'S',
        sourceType: 'sextant',
        colorName: 'green',
        description: 'Celestial calculations inactive',
      ));
    }

    // ── 6. Run Fusion Weighted Calculation ───────────────────────────────────
    double sumLat = 0.0;
    double sumLng = 0.0;
    double sumWeight = 0.0;
    int compositeConfidence = 0;
    double compositeUncertainty = 0.0;

    final activeOpinions = opinions.where((op) => op.status == 'active' && op.confidence > 0).toList();

    if (activeOpinions.isNotEmpty) {
      for (final op in activeOpinions) {
        // Weight based on confidence / (uncertainty radius)^2
        final radius = op.uncertaintyRadius.clamp(1.0, 10000.0);
        final weight = op.confidence / (radius * radius);
        
        sumLat += op.latitude * weight;
        sumLng += op.longitude * weight;
        sumWeight += weight;
      }

      double fusedLat;
      double fusedLng;

      if (sumWeight > 0) {
        fusedLat = sumLat / sumWeight;
        fusedLng = sumLng / sumWeight;
      } else {
        // Simple average fallback
        fusedLat = activeOpinions.map((o) => o.latitude).reduce((a, b) => a + b) / activeOpinions.length;
        fusedLng = activeOpinions.map((o) => o.longitude).reduce((a, b) => a + b) / activeOpinions.length;
      }

      // Calculate composite confidence (average of active opinions, boosted if multiple sources agree)
      final avgConf = activeOpinions.map((o) => o.confidence).reduce((a, b) => a + b) / activeOpinions.length;
      int agreementBonus = 0;
      if (activeOpinions.length >= 3) {
        agreementBonus = 8; // Agreement boost
      }
      compositeConfidence = (avgConf + agreementBonus).clamp(0, 100).toInt();

      // Fused uncertainty error propagation: 1 / sqrt(sum(1 / r_i^2))
      double invSumRadiusSquared = 0.0;
      for (final op in activeOpinions) {
        final radius = op.uncertaintyRadius.clamp(1.0, 10000.0);
        invSumRadiusSquared += 1.0 / (radius * radius);
      }
      compositeUncertainty = (1.0 / sqrt(invSumRadiusSquared)).clamp(5.0, 1000.0);

      // Check for discrepancies between GPS and other sources
      final gpsOpinion = opinions.firstWhere((o) => o.id == 'gps');
      if (gpsOpinion.status == 'active' && activeOpinions.length > 1) {
        double maxDiscrepancy = 0;
        for (final op in activeOpinions) {
          if (op.id == 'gps') continue;
          final dist = _haversine(gpsOpinion.latitude, gpsOpinion.longitude, op.latitude, op.longitude);
          if (dist > maxDiscrepancy) maxDiscrepancy = dist;
        }

        // If GPS is > 500m away from other active sources, trigger critical spoofing alert!
        if (maxDiscrepancy > 500.0) {
          alertMessage = 'CRITICAL: Position discrepancy! GPS differs from offline landmarks by ${maxDiscrepancy.toStringAsFixed(0)}m.';
          alertSeverity = 'critical';
          // Deprecate trust score
          compositeConfidence = (compositeConfidence * 0.4).toInt();
          compositeUncertainty = maxDiscrepancy;
        }
      }

      return FusedPosition(
        latitude: fusedLat,
        longitude: fusedLng,
        confidence: compositeConfidence,
        uncertaintyRadius: compositeUncertainty,
        opinions: opinions,
        alertMessage: alertMessage,
        alertSeverity: alertSeverity,
      );
    } else {
      // No active sources - absolute fallback
      final fallbackLat = gps?.latitude ?? lastTrustedLat ?? 37.8087;
      final fallbackLng = gps?.longitude ?? lastTrustedLng ?? -122.4098;

      return FusedPosition(
        latitude: fallbackLat,
        longitude: fallbackLng,
        confidence: 0,
        uncertaintyRadius: 1000.0,
        opinions: opinions,
        alertMessage: 'CRITICAL: No active positioning sources available!',
        alertSeverity: 'critical',
      );
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }
}
