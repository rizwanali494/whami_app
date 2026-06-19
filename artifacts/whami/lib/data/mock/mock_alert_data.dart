import '../models/trust_event.dart';

class MockAlertData {
  static const List<TrustEvent> events = [
    TrustEvent(
      id: 'a1',
      title: 'GPS Jump Detected',
      severity: 'critical',
      time: '2 min ago',
      description:
          'GPS position jumped 850m in 0.3 seconds — physically impossible. GPS is only one witness; de-weighted to ensure a blended position is trusted.',
      iconName: 'gps_off',
    ),
    TrustEvent(
      id: 'a2',
      title: 'Landmark Anchor Confirmed',
      severity: 'info',
      time: '5 min ago',
      description:
          'Harbor Tower landmark matched. WHAMI cross-checks this physical anchor with GPS to compute a blended, trusted position.',
      iconName: 'location_on',
    ),
    TrustEvent(
      id: 'a3',
      title: 'Magnetic Field Unstable',
      severity: 'warning',
      time: '12 min ago',
      description:
          'Magnetometer field strength spiked to 91.7 µT — well above baseline 48 µT. Possible nearby metal structure or boat engine interference.',
      iconName: 'explore_off',
    ),
    TrustEvent(
      id: 'a4',
      title: 'Region Pack Verified',
      severity: 'info',
      time: '18 min ago',
      description:
          'SF Bay Harbor Pack v2.1 integrity verified. All 847 landmark hashes, magnetic baselines, and celestial tables confirmed intact.',
      iconName: 'inventory_2',
    ),
    TrustEvent(
      id: 'a5',
      title: 'Sky Check Completed',
      severity: 'info',
      time: '24 min ago',
      description:
          'Celestial position fix completed. Error radius: 900m. Position consistent with landmark consensus. Weight: 10% of fusion.',
      iconName: 'wb_sunny',
    ),
    TrustEvent(
      id: 'a6',
      title: 'IMU Path Consistent',
      severity: 'info',
      time: '31 min ago',
      description:
          'IMU dead-reckoning path aligns with landmark fix. Walking / slow boat movement detected. Confidence: 81%.',
      iconName: 'directions_walk',
    ),
    TrustEvent(
      id: 'a7',
      title: 'GPS Signal Restored',
      severity: 'info',
      time: '45 min ago',
      description:
          'GPS signal re-acquired after 3 min loss. Position re-integrated into fusion engine. GPS confidence: 78%.',
      iconName: 'satellite_alt',
    ),
    TrustEvent(
      id: 'a8',
      title: 'Trust Score Drop',
      severity: 'warning',
      time: '1 hr ago',
      description:
          'Overall trust dropped from 82% to 54% during GPS anomaly event. Score recovered after GPS de-weighting.',
      iconName: 'shield',
    ),
  ];
}
