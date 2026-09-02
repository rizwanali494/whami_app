class TrustEvent {
  final String id;
  final String title;
  final String severity; // info, warning, critical
  final DateTime timestamp;
  final String description;
  final String iconName;
  final String? actionHint;
  final bool isOngoing;

  TrustEvent({
    required this.id,
    required this.title,
    required this.severity,
    required this.description,
    required this.iconName,
    this.actionHint,
    this.isOngoing = false,
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

  factory TrustEvent.gpsJump({required double distance}) {
    return TrustEvent(
      id: 'gps_jump_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Jump Detected',
      severity: 'critical',
      description:
          'GPS disagrees with the trusted fix by ${distance.toStringAsFixed(0)} m — physically unlikely.',
      actionHint: 'Move to open sky or verify a nearby landmark.',
      isOngoing: true,
      iconName: 'gps_off',
    );
  }

  factory TrustEvent.gpsLost() {
    return TrustEvent(
      id: 'gps_lost_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Signal Lost',
      severity: 'warning',
      description:
          'GPS unavailable. WHAMI is using landmark, magnetic, IMU, and sky checks.',
      actionHint: 'Seek clearer sky view or start a landmark verify.',
      isOngoing: true,
      iconName: 'satellite_alt',
    );
  }

  factory TrustEvent.gpsRestored({required int confidence}) {
    return TrustEvent(
      id: 'gps_restored_${DateTime.now().millisecondsSinceEpoch}',
      title: 'GPS Signal Restored',
      severity: 'info',
      description:
          'GPS re-acquired and re-integrated. Confidence: $confidence%.',
      actionHint: 'Continue tracking.',
      isOngoing: false,
      iconName: 'satellite_alt',
    );
  }

  factory TrustEvent.landmarkMatched({
    required String landmarkName,
    required int confidence,
  }) {
    return TrustEvent(
      id: 'landmark_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Locked to Real World',
      severity: 'info',
      description:
          '$landmarkName locked as a physical-world anchor ($confidence%). GPS can be cross-checked against it.',
      actionHint: 'If GPS jumps away from this lock, WHAMI will warn you.',
      isOngoing: false,
      iconName: 'lock',
    );
  }

  factory TrustEvent.magneticInterference({required double fieldStrength}) {
    return TrustEvent(
      id: 'mag_interference_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Magnetic Field Unstable',
      severity: 'warning',
      description:
          'Magnetometer spiked to ${fieldStrength.toStringAsFixed(1)} µT — possible metal or electronics nearby.',
      actionHint: 'Step away from vehicles, phones, or metal structures.',
      isOngoing: true,
      iconName: 'explore_off',
    );
  }

  factory TrustEvent.packVerified({required String packName}) {
    return TrustEvent(
      id: 'pack_verified_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Region Pack Verified',
      severity: 'info',
      description:
          '$packName integrity verified. Landmark and magnetic baselines intact.',
      actionHint: 'Activate this pack and start tracking.',
      isOngoing: false,
      iconName: 'inventory_2',
    );
  }

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
      actionHint: dropped
          ? 'Check live alert on Map, or open Verify.'
          : 'Sources are aligning — continue as normal.',
      isOngoing: dropped,
      iconName: 'shield',
    );
  }

  factory TrustEvent.skyCheck({required double errorRadius}) {
    return TrustEvent(
      id: 'sky_check_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Sky Check Completed',
      severity: 'info',
      description:
          'Celestial check finished. Error radius: ${errorRadius.toStringAsFixed(0)}m.',
      actionHint: 'No action needed.',
      isOngoing: false,
      iconName: 'wb_sunny',
    );
  }

  factory TrustEvent.imuConsistent({required int confidence}) {
    return TrustEvent(
      id: 'imu_${DateTime.now().millisecondsSinceEpoch}',
      title: 'IMU Path Consistent',
      severity: 'info',
      description:
          'Motion path aligns with other sources. Confidence: $confidence%.',
      actionHint: 'No action needed.',
      isOngoing: false,
      iconName: 'directions_walk',
    );
  }

  factory TrustEvent.trackingStarted() {
    return TrustEvent(
      id: 'tracking_start_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Live Tracking Started',
      severity: 'info',
      description: 'Sensors activated. Position fusion engine running.',
      actionHint:
          'Watch the trust banner on Map for Reliable / Caution / Unreliable.',
      isOngoing: true,
      iconName: 'gps_fixed',
    );
  }

  factory TrustEvent.trackingStopped() {
    return TrustEvent(
      id: 'tracking_stop_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Live Tracking Stopped',
      severity: 'info',
      description: 'Sensors deactivated. Last position saved.',
      actionHint: 'Tap Start tracking on Map when ready.',
      isOngoing: false,
      iconName: 'gps_off',
    );
  }
}
