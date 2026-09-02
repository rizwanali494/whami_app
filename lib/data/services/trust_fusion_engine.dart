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
  final double? wmmResidualUt;
  final double? baroGpsAltDeltaM;
  final int magneticAgreement;
  final int baroConsistency;
  final int celestialAgreement;
  final bool gnssSuspicious;
  final List<String> sourceHierarchy;

  const FusedPosition({
    required this.latitude,
    required this.longitude,
    required this.confidence,
    required this.uncertaintyRadius,
    required this.opinions,
    required this.alertMessage,
    required this.alertSeverity,
    this.wmmResidualUt,
    this.baroGpsAltDeltaM,
    this.magneticAgreement = 0,
    this.baroConsistency = 0,
    this.celestialAgreement = 0,
    this.gnssSuspicious = false,
    this.sourceHierarchy = const [],
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
    /// Visual landmark anchor used when GPS is unavailable.
    double? landmarkAnchorLat,
    double? landmarkAnchorLng,
    String? landmarkAnchorName,
    /// Optional WMM residual (µT) and agreement score from WmmService.
    double? wmmResidualUt,
    int? wmmAgreementScore,
    String? wmmStatus,
    String? wmmDescription,
  }) {
    final opinions = <PositionOpinion>[];
    String alertMessage = 'Positions aligned. System nominal.';
    String alertSeverity = 'none';
    double? baroGpsAltDeltaM;
    var gnssSuspicious = false;
    var magneticAgreement = 0;
    var baroConsistency = 0;
    var celestialAgreement = 0;

    final hasValidGps = gps != null;
    final hasAnchor =
        landmarkAnchorLat != null && landmarkAnchorLng != null;
    final hasPositionCoords = hasValidGps ||
        hasAnchor ||
        (lastTrustedLat != null && lastTrustedLng != null);

    // ── 1. GPS Position Opinion ──────────────────────────────────────────────
    if (gps != null) {
      String status = 'active';
      String desc = 'Live GPS fix';

      // Detect anomalies (GPS jumps vs last trusted fix)
      if (lastTrustedLat != null && lastTrustedLng != null) {
        final distFromLastTrusted = _haversine(
          lastTrustedLat,
          lastTrustedLng,
          gps.latitude,
          gps.longitude,
        );
        // Physically unlikely jump: large move without matching speed.
        if (distFromLastTrusted > 500 && gps.speed < 30) {
          status = 'unstable';
          desc =
              'GPS jumped ${distFromLastTrusted.toStringAsFixed(0)} m — spoofing suspected.';
          alertMessage =
              'GPS suspicious — don\'t trust this pin. Jump ${distFromLastTrusted.toStringAsFixed(0)} m without matching speed.';
          alertSeverity = distFromLastTrusted > 1000 ? 'critical' : 'warning';
          gnssSuspicious = true;
        }
      }

      opinions.add(
        PositionOpinion.fromGps(
          latitude: gps.latitude,
          longitude: gps.longitude,
          accuracy: gps.accuracy,
          status: status,
          description: desc,
        ),
      );
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'gps',
          name: 'GPS / GNSS',
          shortCode: 'G',
          sourceType: 'gps',
          colorName: 'blue',
          description: 'Waiting for satellite signals',
        ),
      );
    }

    // ── 2. Landmark Matching / Visual Anchor Opinion ─────────────────────────
    // Visual "Lock to Real World" pins an independent lat/lng so a lying GPS
    // pin can be caught by cross-source disagreement.
    if (hasAnchor) {
      final anchorActive = gps == null || gnssSuspicious;
      opinions.add(
        PositionOpinion.fromLandmark(
          latitude: landmarkAnchorLat!,
          longitude: landmarkAnchorLng!,
          confidence: anchorActive ? 90 : 78,
          uncertaintyRadius: 40.0,
          status: 'active',
          description:
              'Locked to real world: ${landmarkAnchorName ?? "landmark"}',
        ),
      );
      if (gps != null) {
        final dist = _haversine(
          landmarkAnchorLat,
          landmarkAnchorLng,
          gps.latitude,
          gps.longitude,
        );
        // Far from locked landmark while still "near" it in the UI → GPS lie.
        if (dist > 250) {
          gnssSuspicious = true;
          alertMessage =
              'GPS suspicious — don\'t trust this pin. GPS is ${dist.toStringAsFixed(0)} m from locked landmark.';
          alertSeverity = dist > 500 ? 'critical' : 'warning';
          // Downgrade the GPS opinion if still marked active.
          final gpsIdx = opinions.indexWhere((o) => o.id == 'gps');
          if (gpsIdx >= 0 && opinions[gpsIdx].status == 'active') {
            opinions[gpsIdx] = opinions[gpsIdx].copyWith(
              status: 'unstable',
              description:
                  'GPS ${dist.toStringAsFixed(0)} m from locked real-world anchor',
              confidence: (opinions[gpsIdx].confidence * 0.4).round(),
            );
          }
        }
      }
    } else if (hasOfflineData && landmarkMatch != null && gps != null) {
      final confidenceScore = (landmarkMatch.confidence * 100).toInt();
      final double estimatedUncertainty = landmarkMatch.distance.clamp(
        10.0,
        150.0,
      );

      // Use the live GPS coords (no random jitter) — landmark match validates
      // proximity; inventing nearby coordinates only degraded trust.
      opinions.add(
        PositionOpinion.fromLandmark(
          latitude: gps.latitude,
          longitude: gps.longitude,
          confidence: confidenceScore,
          uncertaintyRadius: estimatedUncertainty,
          status: 'active',
          description: 'Nearest matched landmark: ${landmarkMatch.name}',
        ),
      );
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'landmark',
          name: 'Landmark / Seamap',
          shortCode: 'L',
          sourceType: 'landmark',
          colorName: 'black',
          description: hasOfflineData
              ? 'No landmarks identified in range'
              : 'No region pack active',
        ),
      );
    }

    // ── 3. Magnetic Grid / WMM Opinion ───────────────────────────────────────
    if (wmmResidualUt != null &&
        wmmAgreementScore != null &&
        magnetometer != null &&
        gps != null) {
      magneticAgreement = wmmAgreementScore;
      final status = wmmStatus ?? 'active';
      if (status == 'unstable') {
        alertMessage =
            wmmDescription ?? 'Magnetic model disagreement detected.';
        if (alertSeverity == 'none') alertSeverity = 'warning';
      }
      opinions.add(
        PositionOpinion.fromMagnetic(
          latitude: gps.latitude,
          longitude: gps.longitude,
          confidence: wmmAgreementScore,
          uncertaintyRadius: status == 'unstable' ? 500.0 : 180.0,
          status: status == 'unstable' ? 'unstable' : 'active',
          description: wmmDescription ??
              'WMM residual ${wmmResidualUt.toStringAsFixed(1)} µT',
        ),
      );
    } else if (hasOfflineData &&
        magneticMatch != null &&
        magnetometer != null &&
        gps != null) {
      // Full cross-check: expected field vs live readings
      final isInterfered =
          magneticMatch.deviation >
          8.0; // deviation > 8 µT is heavy interference
      final status = isInterfered ? 'unstable' : 'active';
      final confidenceScore = isInterfered
          ? 20
          : (magneticMatch.stability * 95).toInt();
      magneticAgreement = confidenceScore;

      String desc =
          'Field deviation: ${magneticMatch.deviation.toStringAsFixed(1)} µT';
      if (isInterfered) {
        desc += ' (Interference detected!)';
        alertMessage =
            'ALERT: Geomagnetic anomalies detected. Metallic interference possible.';
        alertSeverity = 'info';
      }

      // Magnetic lookup gives position validation at the known GPS fix
      opinions.add(
        PositionOpinion.fromMagnetic(
          latitude: gps.latitude,
          longitude: gps.longitude,
          confidence: confidenceScore,
          uncertaintyRadius: isInterfered ? 500.0 : 150.0,
          status: status,
          description: desc,
        ),
      );
    } else if (magnetometer != null) {
      // Live hardware reading — verify-only when we lack real coordinates.
      // Never invent (0,0) as a position vote.
      final strength = magnetometer.fieldStrength;
      final heading = magnetometer.heading;

      int rawConfidence;
      if (strength > 20 && strength < 65) {
        rawConfidence = 72;
      } else if (strength > 10 && strength < 100) {
        rawConfidence = 50;
      } else {
        rawConfidence = 25;
      }

      if (hasPositionCoords && gps != null) {
        magneticAgreement = rawConfidence;
        opinions.add(
          PositionOpinion.fromMagnetic(
            latitude: gps.latitude,
            longitude: gps.longitude,
            confidence: rawConfidence,
            uncertaintyRadius: 300.0,
            status: 'active',
            description:
                'Live: ${heading.toStringAsFixed(0)}° heading, '
                '${strength.toStringAsFixed(1)} µT'
                '${!hasOfflineData ? ' (no pack for cross-check)' : ''}',
          ),
        );
      } else {
        // Status "verify" is shown in the UI but excluded from lat/lng fusion.
        opinions.add(
          PositionOpinion.fromMagnetic(
            latitude: 0,
            longitude: 0,
            confidence: rawConfidence,
            uncertaintyRadius: 300.0,
            status: 'verify',
            description:
                'Compass verify-only: ${heading.toStringAsFixed(0)}° / '
                '${strength.toStringAsFixed(1)} µT — no position coords',
          ),
        );
      }
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'magnetic',
          name: 'Magnetic Field',
          shortCode: 'M',
          sourceType: 'magnetic',
          colorName: 'red',
          description: 'No magnetometer signal',
        ),
      );
    }

    // ── 4. IMU Dead-Reckoning Opinion ────────────────────────────────────────
    if (imu != null && lastTrustedLat != null && lastTrustedLng != null) {
      // Integrate IMU displacement into coordinates
      // 1 degree latitude ~ 111,000 meters. 1 degree longitude ~ 111,000 * cos(lat) meters.
      final latRad = lastTrustedLat * pi / 180;
      final newLat = lastTrustedLat + (imu.displacementY / 111000.0);
      final newLng =
          lastTrustedLng + (imu.displacementX / (111000.0 * cos(latRad)));

      // Confidence slowly decays as displacement grows to represent drift
      final driftDistance = sqrt(
        imu.displacementX * imu.displacementX +
            imu.displacementY * imu.displacementY,
      );
      final double uncertainty = (30.0 + (driftDistance * 0.1)).clamp(
        30.0,
        1000.0,
      );
      final confidenceScore = (85 - (driftDistance * 0.05).toInt()).clamp(
        10,
        90,
      );

      opinions.add(
        PositionOpinion.fromImu(
          latitude: newLat,
          longitude: newLng,
          confidence: confidenceScore,
          uncertaintyRadius: uncertainty,
          status: 'active',
          description:
              'Dead reckoning. Drift: ${driftDistance.toStringAsFixed(0)}m',
        ),
      );
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'imu',
          name: 'IMU Movement',
          shortCode: 'I',
          sourceType: 'imu',
          colorName: 'purple',
          description: 'IMU tracking inactive',
        ),
      );
    }

    // ── 5. Celestial Alignment Opinion ───────────────────────────────────────
    if (sky != null && gps != null) {
      celestialAgreement = sky.confidence;
      // Coarse offline verification at the GPS fix — no invented jitter.
      opinions.add(
        PositionOpinion.fromSky(
          latitude: gps.latitude,
          longitude: gps.longitude,
          confidence: sky.confidence,
          uncertaintyRadius: 800.0,
          status: 'active',
          description:
              'Celestial azimuth alignment: Sun ${sky.sunAzimuth.toStringAsFixed(0)}°',
        ),
      );
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'sextant',
          name: 'Sextant / Sky',
          shortCode: 'S',
          sourceType: 'sextant',
          colorName: 'green',
          description: 'Celestial calculations inactive',
        ),
      );
    }

    // ── 5b. Barometric vertical consistency ──────────────────────────────────
    if (barometer != null && gps != null) {
      final delta = (barometer.estimatedAltitude - gps.altitude).abs();
      baroGpsAltDeltaM = delta;
      // Vertical witness only — pins to GPS lat/lng; does not invent horizontal fix.
      late final int conf;
      late final String status;
      late final String desc;
      if (delta <= 40) {
        conf = 85;
        status = 'active';
        desc =
            'Baro/GPS alt agree (Δ ${delta.toStringAsFixed(0)} m)';
      } else if (delta <= 120) {
        conf = 55;
        status = 'active';
        desc =
            'Baro/GPS soft mismatch (Δ ${delta.toStringAsFixed(0)} m)';
      } else {
        conf = 20;
        status = 'unstable';
        desc =
            'Baro/GPS altitude conflict (Δ ${delta.toStringAsFixed(0)} m)';
        if (alertSeverity == 'none' || alertSeverity == 'info') {
          alertMessage = desc;
          alertSeverity = 'warning';
        }
      }
      baroConsistency = conf;
      opinions.add(
        PositionOpinion.fromBarometer(
          latitude: gps.latitude,
          longitude: gps.longitude,
          confidence: conf,
          uncertaintyRadius: 250.0 + delta,
          status: status,
          description: desc,
        ),
      );
    } else {
      opinions.add(
        PositionOpinion.unavailable(
          id: 'baro',
          name: 'Barometric',
          shortCode: 'B',
          sourceType: 'baro',
          colorName: 'teal',
          description: barometer == null
              ? 'No barometer reading'
              : 'Baro needs GPS altitude for consistency check',
        ),
      );
    }

    // ── 6. Run Fusion Weighted Calculation ───────────────────────────────────
    double sumLat = 0.0;
    double sumLng = 0.0;
    double sumWeight = 0.0;
    int compositeConfidence = 0;
    double compositeUncertainty = 0.0;

    // Exclude verify-only / unavailable / 0,0 placeholder coords from position.
    final activeOpinions = opinions
        .where(
          (op) =>
              op.status == 'active' &&
              op.confidence > 0 &&
              !(op.latitude == 0 && op.longitude == 0),
        )
        .toList();

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
        fusedLat =
            activeOpinions.map((o) => o.latitude).reduce((a, b) => a + b) /
            activeOpinions.length;
        fusedLng =
            activeOpinions.map((o) => o.longitude).reduce((a, b) => a + b) /
            activeOpinions.length;
      }

      // Calculate composite confidence (average of active opinions, boosted if multiple sources agree)
      final avgConf =
          activeOpinions.map((o) => o.confidence).reduce((a, b) => a + b) /
          activeOpinions.length;
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
      compositeUncertainty = (1.0 / sqrt(invSumRadiusSquared)).clamp(
        5.0,
        1000.0,
      );

      // Check for discrepancies between GPS and other sources
      final gpsOpinion = opinions.firstWhere((o) => o.id == 'gps');
      if (gpsOpinion.status == 'active' && activeOpinions.length > 1) {
        double maxDiscrepancy = 0;
        for (final op in activeOpinions) {
          if (op.id == 'gps') continue;
          final dist = _haversine(
            gpsOpinion.latitude,
            gpsOpinion.longitude,
            op.latitude,
            op.longitude,
          );
          if (dist > maxDiscrepancy) maxDiscrepancy = dist;
        }

        // If GPS is > 500m away from other active sources, trigger critical spoofing alert!
        if (maxDiscrepancy > 500.0) {
          alertMessage =
              'GPS suspicious — don\'t trust this pin. GPS differs from witnesses by ${maxDiscrepancy.toStringAsFixed(0)} m.';
          alertSeverity = 'critical';
          gnssSuspicious = true;
          // Deprecate trust score
          compositeConfidence = (compositeConfidence * 0.4).toInt();
          compositeUncertainty = maxDiscrepancy;
        }
      }

      final hierarchy = <String>[];
      for (final op in activeOpinions) {
        hierarchy.add('${op.shortCode}:${op.confidence}');
      }
      hierarchy.sort((a, b) {
        final ca = int.tryParse(a.split(':').last) ?? 0;
        final cb = int.tryParse(b.split(':').last) ?? 0;
        return cb.compareTo(ca);
      });

      return FusedPosition(
        latitude: fusedLat,
        longitude: fusedLng,
        confidence: compositeConfidence,
        uncertaintyRadius: compositeUncertainty,
        opinions: opinions,
        alertMessage: alertMessage,
        alertSeverity: alertSeverity,
        wmmResidualUt: wmmResidualUt,
        baroGpsAltDeltaM: baroGpsAltDeltaM,
        magneticAgreement: magneticAgreement,
        baroConsistency: baroConsistency,
        celestialAgreement: celestialAgreement,
        gnssSuspicious: gnssSuspicious,
        sourceHierarchy: hierarchy,
      );
    } else {
      // No active sources - absolute fallback
      final fallbackLat = gps?.latitude ?? lastTrustedLat ?? 37.8087;
      final fallbackLng = gps?.longitude ?? lastTrustedLng ?? -122.4098;

      // Prefer last trusted fix when GPS itself is the suspicious source.
      final useTrusted = gnssSuspicious &&
          lastTrustedLat != null &&
          lastTrustedLng != null;

      return FusedPosition(
        latitude: useTrusted ? lastTrustedLat : fallbackLat,
        longitude: useTrusted ? lastTrustedLng : fallbackLng,
        confidence: gnssSuspicious ? 25 : 0,
        uncertaintyRadius: gnssSuspicious ? 1000.0 : 1000.0,
        opinions: opinions,
        alertMessage: gnssSuspicious
            ? alertMessage
            : 'CRITICAL: No active positioning sources available!',
        alertSeverity: gnssSuspicious ? alertSeverity : 'critical',
        wmmResidualUt: wmmResidualUt,
        baroGpsAltDeltaM: baroGpsAltDeltaM,
        magneticAgreement: magneticAgreement,
        baroConsistency: baroConsistency,
        celestialAgreement: celestialAgreement,
        gnssSuspicious: gnssSuspicious,
        sourceHierarchy: const [],
      );
    }
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }
}
