class TrustEvent {
  final String id;
  final String title;
  final String severity; // info, warning, critical
  final DateTime timestamp;
  final String description;
  final String iconName;

  TrustEvent({
    required this.id,
    required this.title,
    required this.severity,
    required this.description,
    required this.iconName,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// GPS jump detected
  factory TrustEvent.gpsJump({required double distance}) {
    return TrustEvent(
      id: 'gps_jump_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Jump Detected',
      severity: 'critical',
      description:
          'GPS position jumped ${distance.toStringAsFixed(0)}m — physically impossible. '
          'GPS de-weighted to ensure blended position is trusted.',
      iconName: 'gps_off',
    );
  }

  /// GPS signal lost
  factory TrustEvent.gpsLost() {
    return TrustEvent(
      id: 'gps_lost_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Signal Lost',
      severity: 'warning',
      description:
          'GPS signal unavailable. WHAMI is using landmark, magnetic, IMU, '
          'and sky checks to maintain position.',
      iconName: 'satellite_alt',
    );
  }

  /// GPS signal restored
  factory TrustEvent.gpsRestored({required int confidence}) {
    return TrustEvent(
      id: 'gps_restored_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Signal Restored',
      severity: 'info',
      description:
          'GPS signal re-acquired. Position re-integrated into fusion '
          'engine. GPS confidence: $confidence%.',
      iconName: 'satellite_alt',
    );
  }

  /// Landmark matched
  factory TrustEvent.landmarkMatched({
    required String landmarkName,
    required int confidence,
  }) {
    return TrustEvent(
      id: 'landmark_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Landmark Anchor Confirmed',
      severity: 'info',
      description:
          '$landmarkName matched. WHAMI cross-checks this physical anchor '
          'with GPS to compute a blended, trusted position. Confidence: $confidence%.',
      iconName: 'location_on',
    );
  }

  /// Magnetic interference
  factory TrustEvent.magneticInterference({required double fieldStrength}) {
    return TrustEvent(
      id: 'mag_interference_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Magnetic Field Unstable',
      severity: 'warning',
      description:
          'Magnetometer field strength spiked to ${fieldStrength.toStringAsFixed(1)} µT. '
          'Possible nearby metal structure or electronics interference.',
      iconName: 'explore_off',
    );
  }

  /// Region pack verified
  factory TrustEvent.packVerified({required String packName}) {
    return TrustEvent(
      id: 'pack_verified_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Region Pack Verified',
      severity: 'info',
      description:
          '$packName integrity verified. All landmark, magnetic baselines, '
          'and chart data confirmed intact.',
      iconName: 'inventory_2',
    );
  }

  /// Trust score change
  factory TrustEvent.trustChange({
    required int oldScore,
    required int newScore,
  }) {
    final dropped = newScore < oldScore;
    return TrustEvent(
      id: 'trust_change_${DateTime.now().millisecondsSinceEpoch}',
      title: dropped ? 'Trust Score Drop' : 'Trust Score Improved',
      severity: dropped ? 'warning' : 'info',
      description:
          'Overall trust ${dropped ? "dropped" : "improved"} from $oldScore% to $newScore%.',
      iconName: 'shield',
    );
  }

  /// Sky check completed
  factory TrustEvent.skyCheck({required double errorRadius}) {
    return TrustEvent(
      id: 'sky_check_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Sky Check Completed',
      severity: 'info',
      description:
          'Celestial position fix completed. Error radius: ${errorRadius.toStringAsFixed(0)}m. '
          'Position consistent with landmark consensus.',
      iconName: 'wb_sunny',
    );
  }

  /// IMU consistency
  factory TrustEvent.imuConsistent({required int confidence}) {
    return TrustEvent(
      id: 'imu_${DateTime.now().millisecondsSinceEpoch}',
      title: 'IMU Path Consistent',
      severity: 'info',
      description:
          'IMU dead-reckoning path aligns with other sources. '
          'Confidence: $confidence%.',
      iconName: 'directions_walk',
    );
  }

  /// Tracking started
  factory TrustEvent.trackingStarted() {
    return TrustEvent(
      id: 'tracking_start_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Live Tracking Started',
      severity: 'info',
      description: 'All sensors activated. Position fusion engine running.',
      iconName: 'gps_fixed',
    );
  }

  /// Tracking stopped
  factory TrustEvent.trackingStopped() {
    return TrustEvent(
      id: 'tracking_stop_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Live Tracking Stopped',
      severity: 'info',
      description: 'Sensors deactivated. Last position saved.',
      iconName: 'gps_off',
    );
  }
}
