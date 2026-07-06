import 'dart:math';

/// Reading from astronomical calculations representing sun/moon angles & position reliability
class SkyReading {
  final double sunElevation; // degrees
  final double sunAzimuth; // degrees
  final double moonElevation; // degrees
  final double moonAzimuth; // degrees
  final int confidence; // 0-100% based on calculation stability & time of day/night
  final DateTime timestamp;

  const SkyReading({
    required this.sunElevation,
    required this.sunAzimuth,
    required this.moonElevation,
    required this.moonAzimuth,
    required this.confidence,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Sky(Sun el: ${sunElevation.toStringAsFixed(1)}°, az: ${sunAzimuth.toStringAsFixed(1)}°)';
}

/// Service that computes celestial body azimuth/elevation offline using device clock & approximate GPS
class SkyService {
  SkyReading? _lastReading;
  String _statusMessage = 'Calculations offline ready';

  SkyReading? get lastReading => _lastReading;
  String get statusMessage => _statusMessage;

  /// Performs solar and lunar calculations using standard astronomical algorithms
  SkyReading calculateCelestialPositions({
    required double latitude,
    required double longitude,
    required DateTime time,
  }) {
    // 1. Calculate Sun Position
    final sunCoords = _calculateSunPosition(latitude, longitude, time);
    
    // 2. Calculate Moon Position (simplified approximation)
    final moonCoords = _calculateMoonPosition(latitude, longitude, time);

    // 3. Compute confidence score
    // Celestial alignment is higher trust when the body is visible (elevation > 0)
    // and when the time is not in transitional astronomical twilight unless clean horizons.
    int confidence = 85;
    if (sunCoords['elevation']! < -18 && moonCoords['elevation']! < 0) {
      // Midnight with no moon visible = low celestial tracking confidence
      confidence = 30;
    } else if (sunCoords['elevation']! > 5) {
      // Broad daylight, sun is clearly visible
      confidence = 90;
    }

    final reading = SkyReading(
      sunElevation: sunCoords['elevation']!,
      sunAzimuth: sunCoords['azimuth']!,
      moonElevation: moonCoords['elevation']!,
      moonAzimuth: moonCoords['azimuth']!,
      confidence: confidence,
      timestamp: time,
    );

    _lastReading = reading;
    _statusMessage = 'Sun: ${sunCoords['elevation']!.toStringAsFixed(1)}° El / ${sunCoords['azimuth']!.toStringAsFixed(1)}° Az';
    return reading;
  }

  /// Calculates Sun position (elevation & azimuth)
  /// Returns a map with 'elevation' and 'azimuth' in degrees
  Map<String, double> _calculateSunPosition(double lat, double lng, DateTime utcTime) {
    final utc = utcTime.toUtc();
    
    // Day of the year
    final daysInYear = utc.difference(DateTime.utc(utc.year, 1, 1)).inDays + 1;
    
    // Fractional year in radians
    final gamma = (2 * pi / 365) * (daysInYear - 1 + (utc.hour - 12) / 24);
    
    // Equation of time in minutes
    final eqTime = 229.18 * (0.000075 +
        0.001868 * cos(gamma) -
        0.032077 * sin(gamma) -
        0.014615 * cos(2 * gamma) -
        0.040849 * sin(2 * gamma));
        
    // Solar declination angle in radians
    final decl = 0.006918 -
        0.399912 * cos(gamma) +
        0.070257 * sin(gamma) -
        0.006758 * cos(2 * gamma) +
        0.000907 * sin(2 * gamma) -
        0.002697 * cos(3 * gamma) +
        0.00148 * sin(3 * gamma);

    // Time offset in minutes
    final timeOffset = eqTime + 4 * lng;
    
    // True solar time in minutes
    final tst = utc.hour * 60 + utc.minute + utc.second / 60 + timeOffset;
    
    // Hour angle in degrees
    var ha = (tst / 4) - 180;
    if (ha < -180) ha += 360;
    if (ha > 180) ha -= 360;

    final latRad = lat * pi / 180;
    final haRad = ha * pi / 180;

    // Zenith angle
    final cosZenith = sin(latRad) * sin(decl) + cos(latRad) * cos(decl) * cos(haRad);
    final zenithRad = acos(cosZenith.clamp(-1.0, 1.0));
    final elevation = 90 - (zenithRad * 180 / pi);

    // Azimuth angle
    final cosAzimuth = (sin(decl) - sin(latRad) * cosZenith) / (cos(latRad) * sin(zenithRad));
    var azimuthRad = acos(cosAzimuth.clamp(-1.0, 1.0));
    var azimuth = azimuthRad * 180 / pi;

    if (ha > 0) {
      azimuth = 360 - azimuth;
    } else {
      azimuth = azimuth;
    }

    return {
      'elevation': elevation,
      'azimuth': azimuth,
    };
  }

  /// Calculates Moon position (Simplified approximation for offline use)
  Map<String, double> _calculateMoonPosition(double lat, double lng, DateTime utcTime) {
    // A simple approximation for the moon's position relative to the sun.
    // The moon moves ~13.18 degrees per day relative to stars.
    final utc = utcTime.toUtc();
    final dayOfCycle = (utc.difference(DateTime.utc(2026, 1, 1)).inDays) % 29.53; // Moon synodic period
    
    // Approximate phase offset in degrees (0-360)
    final phaseOffset = (dayOfCycle / 29.53) * 360;
    
    // Estimate moon coordinates relative to sun coordinates
    final sunCoords = _calculateSunPosition(lat, lng, utcTime);
    
    // Rotate sun azimuth by moon phase
    var moonAzimuth = (sunCoords['azimuth']! + phaseOffset) % 360;
    
    // Simple elevation shift based on lunar phase (offset from sun height)
    final phaseRad = phaseOffset * pi / 180;
    var moonElevation = sunCoords['elevation']! * cos(phaseRad);

    return {
      'elevation': moonElevation,
      'azimuth': moonAzimuth,
    };
  }
}
