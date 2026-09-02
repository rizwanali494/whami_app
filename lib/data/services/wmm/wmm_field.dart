/// WMM field components in nT (nanotesla) and angles in degrees.
class WmmField {
  /// North component (nT), geodetic.
  final double x;

  /// East component (nT), geodetic.
  final double y;

  /// Down component (nT), geodetic.
  final double z;

  /// Horizontal intensity H (nT).
  final double h;

  /// Total intensity F (nT).
  final double f;

  /// Declination D (degrees).
  final double declination;

  /// Inclination I (degrees).
  final double inclination;

  /// Model epoch year (e.g. 2025.0).
  final double epoch;

  /// Decimal year used for evaluation.
  final double decimalYear;

  const WmmField({
    required this.x,
    required this.y,
    required this.z,
    required this.h,
    required this.f,
    required this.declination,
    required this.inclination,
    required this.epoch,
    required this.decimalYear,
  });

  /// Total field in microtesla (phone magnetometer units).
  double get fMicroTesla => f / 1000.0;

  @override
  String toString() =>
      'WmmField(F=${f.toStringAsFixed(1)} nT, D=${declination.toStringAsFixed(1)}°)';
}

/// Residual between measured field and WMM prediction.
class WmmResidual {
  final WmmField model;
  final double measuredFMicroTesla;
  final double residualMicroTesla;
  final int agreementScore; // 0–100
  final String status; // active, unstable, verify, unavailable
  final String description;

  const WmmResidual({
    required this.model,
    required this.measuredFMicroTesla,
    required this.residualMicroTesla,
    required this.agreementScore,
    required this.status,
    required this.description,
  });
}
