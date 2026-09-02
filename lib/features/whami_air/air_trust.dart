import 'package:flutter/material.dart';
import '../../core/trust/trust_summary.dart';

/// Cockpit-simple advisory trust states for WHAMI-Air.
enum AirTrustBand {
  green,
  amber,
  red,
  grey,
}

extension AirTrustBandX on AirTrustBand {
  String get label {
    switch (this) {
      case AirTrustBand.green:
        return 'AGREE';
      case AirTrustBand.amber:
        return 'UNCERTAIN';
      case AirTrustBand.red:
        return 'DISAGREE';
      case AirTrustBand.grey:
        return 'NO EVIDENCE';
    }
  }

  String get pilotLine {
    switch (this) {
      case AirTrustBand.green:
        return 'Passive witnesses agree with non-GNSS track';
      case AirTrustBand.amber:
        return 'Uncertainty growing — cross-check instruments';
      case AirTrustBand.red:
        return 'GNSS likely false / sources disagree';
      case AirTrustBand.grey:
        return 'Not enough evidence for advisory trust';
    }
  }

  Color get color {
    switch (this) {
      case AirTrustBand.green:
        return const Color(0xFF2E7D32);
      case AirTrustBand.amber:
        return const Color(0xFFF9A825);
      case AirTrustBand.red:
        return const Color(0xFFC62828);
      case AirTrustBand.grey:
        return const Color(0xFF78909C);
    }
  }

}

AirTrustBand airTrustBandFrom({
  required int trustScore,
  required TrustLevel level,
  required bool isTracking,
  required int activeWitnesses,
}) {
  if (!isTracking || activeWitnesses == 0) return AirTrustBand.grey;
  if (level == TrustLevel.unreliable || trustScore < 55) {
    return AirTrustBand.red;
  }
  if (level == TrustLevel.caution || trustScore < 75) {
    return AirTrustBand.amber;
  }
  return AirTrustBand.green;
}

/// Snapshot of advisory outputs for Air UI / recorder / EFB.
class AirTrustSnapshot {
  final AirTrustBand band;
  final int positionTrust;
  final double confidenceRadiusM;
  final bool gnssSuspicious;
  final bool gnssUnavailable;
  final int magneticAgreement;
  final int baroConsistency;
  final int celestialAgreement;
  final double? wmmResidualUt;
  final double? baroGpsAltDeltaM;
  final List<String> sourceHierarchy;
  final String advisoryMessage;

  const AirTrustSnapshot({
    required this.band,
    required this.positionTrust,
    required this.confidenceRadiusM,
    required this.gnssSuspicious,
    required this.gnssUnavailable,
    required this.magneticAgreement,
    required this.baroConsistency,
    required this.celestialAgreement,
    required this.wmmResidualUt,
    required this.baroGpsAltDeltaM,
    required this.sourceHierarchy,
    required this.advisoryMessage,
  });

  Map<String, dynamic> toJson() => {
        'band': band.name,
        'positionTrust': positionTrust,
        'confidenceRadiusM': confidenceRadiusM,
        'gnssSuspicious': gnssSuspicious,
        'gnssUnavailable': gnssUnavailable,
        'magneticAgreement': magneticAgreement,
        'baroConsistency': baroConsistency,
        'celestialAgreement': celestialAgreement,
        'wmmResidualUt': wmmResidualUt,
        'baroGpsAltDeltaM': baroGpsAltDeltaM,
        'sourceHierarchy': sourceHierarchy,
        'advisoryMessage': advisoryMessage,
      };
}
