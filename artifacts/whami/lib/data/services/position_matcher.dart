import 'dart:math';

/// Result of matching live position against local region landmark data
class LandmarkMatch {
  final String name;
  final double distance; // meters
  final double confidence; // matching reliability (0.0 to 1.0)

  const LandmarkMatch({
    required this.name,
    required this.distance,
    required this.confidence,
  });
}

/// Result of matching live position against local geomagnetic grid
class MagneticMatch {
  final double expectedStrength; // µT
  final double stability; // stability of magnetic grid (0.0 to 1.0)
  final double deviation; // difference from live magnetometer reading

  const MagneticMatch({
    required this.expectedStrength,
    required this.stability,
    required this.deviation,
  });
}

/// Result of matching live position against local seamap navigational lines
class SeamapMatch {
  final String laneName;
  final double distanceToLane; // meters

  const SeamapMatch({
    required this.laneName,
    required this.distanceToLane,
  });
}

/// Matches live coordinates against loaded GeoJSON files (landmarks, magnetic grid, channels)
class PositionMatcher {
  /// Haversine distance helper
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  /// Find nearest physical landmark from GeoJSON features list
  LandmarkMatch? matchLandmarks({
    required double latitude,
    required double longitude,
    required Map<String, dynamic>? landmarksGeoJson,
  }) {
    if (landmarksGeoJson == null) return null;
    final features = landmarksGeoJson['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) return null;

    double minDistance = double.infinity;
    String closestName = 'Unknown';
    double confidence = 0.0;

    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      final props = feature['properties'] as Map<String, dynamic>?;
      if (coords == null || coords.length < 2 || props == null) continue;

      final double landmarkLng = coords[0] as double;
      final double landmarkLat = coords[1] as double;
      final double dist = _haversine(latitude, longitude, landmarkLat, landmarkLng);

      if (dist < minDistance) {
        minDistance = dist;
        closestName = props['name'] as String? ?? 'Unnamed Landmark';
        confidence = (props['confidence'] as num?)?.toDouble() ?? 0.8;
      }
    }

    if (minDistance == double.infinity) return null;
    return LandmarkMatch(name: closestName, distance: minDistance, confidence: confidence);
  }

  /// Interpolate expected magnetic strength and stability from grid GeoJSON
  /// We find the closest grid point, or do a simple distance-weighted interpolation of the nearest points
  MagneticMatch? matchMagnetic({
    required double latitude,
    required double longitude,
    required double liveStrength,
    required Map<String, dynamic>? magneticGeoJson,
  }) {
    if (magneticGeoJson == null) return null;
    final features = magneticGeoJson['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) return null;

    double totalWeight = 0.0;
    double weightedStrength = 0.0;
    double weightedStability = 0.0;
    double closestDistance = double.infinity;

    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List<dynamic>?;
      final props = feature['properties'] as Map<String, dynamic>?;
      if (coords == null || coords.length < 2 || props == null) continue;

      final double gridLng = coords[0] as double;
      final double gridLat = coords[1] as double;
      final double dist = _haversine(latitude, longitude, gridLat, gridLng);

      if (dist < closestDistance) {
        closestDistance = dist;
      }

      // If exact match (extremely close), return early
      if (dist < 10.0) {
        final expected = (props['reading_uT'] as num).toDouble();
        final stability = (props['stability'] as num).toDouble();
        return MagneticMatch(
          expectedStrength: expected,
          stability: stability,
          deviation: (liveStrength - expected).abs(),
        );
      }

      // Inverse distance weighting interpolation (capped window of influence e.g. 50km)
      if (dist < 50000.0) {
        final weight = 1.0 / (dist * dist);
        totalWeight += weight;
        weightedStrength += (props['reading_uT'] as num).toDouble() * weight;
        weightedStability += (props['stability'] as num).toDouble() * weight;
      }
    }

    if (totalWeight == 0.0) return null;

    final expected = weightedStrength / totalWeight;
    final stability = weightedStability / totalWeight;

    return MagneticMatch(
      expectedStrength: expected,
      stability: stability,
      deviation: (liveStrength - expected).abs(),
    );
  }

  /// Calculates shortest distance from coordinate point to line strings in seamap GeoJSON
  SeamapMatch? matchSeamap({
    required double latitude,
    required double longitude,
    required Map<String, dynamic>? seamapGeoJson,
  }) {
    if (seamapGeoJson == null) return null;
    final features = seamapGeoJson['features'] as List<dynamic>?;
    if (features == null || features.isEmpty) return null;

    double minDistance = double.infinity;
    String closestLane = 'Open Water';

    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final type = geometry?['type'] as String?;
      final props = feature['properties'] as Map<String, dynamic>?;
      if (type != 'LineString' || props == null) continue;

      final coords = geometry?['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) continue;

      // Find the distance to this LineString segment by checking distance to all vertices
      // For simplicity in offline calculations, we compute distance to all vertices and line segment midpoints
      for (int i = 0; i < coords.length; i++) {
        final point = coords[i] as List<dynamic>;
        final double vLng = point[0] as double;
        final double vLat = point[1] as double;
        final double dist = _haversine(latitude, longitude, vLat, vLng);
        if (dist < minDistance) {
          minDistance = dist;
          closestLane = props['name'] as String? ?? 'Navigation Channel';
        }

        // Midpoint check for segments
        if (i < coords.length - 1) {
          final nextPoint = coords[i + 1] as List<dynamic>;
          final double nvLng = nextPoint[0] as double;
          final double nvLat = nextPoint[1] as double;
          final double midLat = (vLat + nvLat) / 2.0;
          final double midLng = (vLng + nvLng) / 2.0;
          final double midDist = _haversine(latitude, longitude, midLat, midLng);
          if (midDist < minDistance) {
            minDistance = midDist;
            closestLane = props['name'] as String? ?? 'Navigation Channel';
          }
        }
      }
    }

    if (minDistance == double.infinity) return null;
    return SeamapMatch(laneName: closestLane, distanceToLane: minDistance);
  }
}
