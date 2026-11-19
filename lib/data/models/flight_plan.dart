import 'dart:convert';
import 'dart:math';

/// One named point on a pilot task / flight plan.
class FlightWaypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const FlightWaypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  FlightWaypoint copyWith({
    String? name,
    double? latitude,
    double? longitude,
  }) {
    return FlightWaypoint(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory FlightWaypoint.fromJson(Map<String, dynamic> json) {
    return FlightWaypoint(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'WP',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

/// Ordered A→B task the pilot bookmarks and saves.
class FlightPlan {
  final String id;
  final String name;
  final List<FlightWaypoint> waypoints;
  final DateTime updatedAt;

  const FlightPlan({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.updatedAt,
  });

  bool get hasRoute => waypoints.length >= 2;
  bool get isEmpty => waypoints.isEmpty;

  FlightPlan copyWith({
    String? name,
    List<FlightWaypoint>? waypoints,
    DateTime? updatedAt,
  }) {
    return FlightPlan(
      id: id,
      name: name ?? this.name,
      waypoints: waypoints ?? this.waypoints,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory FlightPlan.fromJson(Map<String, dynamic> json) {
    final wps = (json['waypoints'] as List<dynamic>? ?? [])
        .map((e) => FlightWaypoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return FlightPlan(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Flight plan',
      waypoints: wps,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory FlightPlan.fromJsonString(String raw) =>
      FlightPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  factory FlightPlan.empty({String? name}) {
    final now = DateTime.now();
    return FlightPlan(
      id: 'plan_${now.millisecondsSinceEpoch}',
      name: name ??
          'Travel route ${now.hour.toString().padLeft(2, '0')}'
              '${now.minute.toString().padLeft(2, '0')}',
      waypoints: const [],
      updatedAt: now,
    );
  }

  /// Great-circle length of the polyline in meters.
  double get totalLengthM {
    if (waypoints.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      sum += haversineM(
        waypoints[i - 1].latitude,
        waypoints[i - 1].longitude,
        waypoints[i].latitude,
        waypoints[i].longitude,
      );
    }
    return sum;
  }

  /// Length of each leg (between consecutive pins), meters.
  List<double> get legLengthsM {
    if (waypoints.length < 2) return const [];
    final out = <double>[];
    for (var i = 1; i < waypoints.length; i++) {
      out.add(
        haversineM(
          waypoints[i - 1].latitude,
          waypoints[i - 1].longitude,
          waypoints[i].latitude,
          waypoints[i].longitude,
        ),
      );
    }
    return out;
  }

  double get totalLengthNm => totalLengthM / 1852.0;

  /// Compact aviation-style coordinate, e.g. `35°48.7'S 145°36.5'E`.
  static String formatCoord(double lat, double lng) {
    String fmt(double v, String pos, String neg) {
      final hemi = v >= 0 ? pos : neg;
      final a = v.abs();
      final deg = a.floor();
      final min = (a - deg) * 60;
      return "$deg°${min.toStringAsFixed(1)}'$hemi";
    }

    return '${fmt(lat, 'N', 'S')} ${fmt(lng, 'E', 'W')}';
  }

  static String formatDistance(double meters) {
    if (meters >= 1852) {
      final nm = meters / 1852.0;
      final km = meters / 1000.0;
      return '${nm.toStringAsFixed(nm >= 10 ? 0 : 1)} NM · ${km.toStringAsFixed(1)} km';
    }
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  static double haversineM(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
