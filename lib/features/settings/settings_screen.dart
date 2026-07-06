import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/connectivity_status.dart';
import '../../data/repositories/whami_repository.dart';

class SettingsScreen extends StatefulWidget {
  final WhamiRepository repository;

  const SettingsScreen({super.key, required this.repository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useMetric = true;

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.repository.getTrustBreakdown();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            title: const Text(
              'Trust Details & Settings',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // Trust formula card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TrustFormulaCard(breakdown: breakdown),
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Settings',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.wifi, color: AppColors.gps),
                        title: const Text('Connectivity Mode'),
                        subtitle: Text(
                          widget.repository.connectivityMode == ConnectivityMode.online
                              ? 'Online (All sources active)'
                              : widget.repository.connectivityMode == ConnectivityMode.offline
                                  ? 'Offline (Local pack verified)'
                                  : 'Limited (GPS only, pack disabled)'
                        ),
                        trailing: DropdownButton<ConnectivityMode>(
                          value: widget.repository.connectivityMode,
                          underline: const SizedBox.shrink(),
                          dropdownColor: AppColors.headerBg,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          onChanged: (mode) {
                            if (mode != null) {
                              widget.repository.connectivityMode = mode;
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                              value: ConnectivityMode.online,
                              child: Text('Online', style: TextStyle(color: Colors.white)),
                            ),
                            DropdownMenuItem(
                              value: ConnectivityMode.offline,
                              child: Text('Offline', style: TextStyle(color: Colors.white)),
                            ),
                            DropdownMenuItem(
                              value: ConnectivityMode.limited,
                              child: Text('Limited', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.info_outline, color: AppColors.gps),
                        title: const Text('App Mode'),
                        subtitle: const Text('Live Sensors (Offline Focused)'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.trustHigh.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.trustHigh.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: AppColors.trustHigh,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 16),
                      SwitchListTile(
                        secondary: const Icon(Icons.straighten, color: AppColors.imu),
                        title: const Text('Units'),
                        subtitle: Text(_useMetric ? 'Metric (m, km)' : 'Imperial (ft, mi)'),
                        value: _useMetric,
                        activeThumbColor: AppColors.headerBg,
                        onChanged: (val) => setState(() => _useMetric = val),
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.storage, color: AppColors.sextant),
                        title: const Text('Offline Pack Storage'),
                        subtitle: const Text('142 MB / 2.0 GB used'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {},
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.magnetic),
                        title: const Text('Privacy'),
                        subtitle: const Text('No data leaves your device in prototype mode'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {},
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Disclaimer',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.alertWarning,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.alertWarningBorder.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning_amber_rounded,
                                color: AppColors.alertWarningBorder, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Important Disclaimer',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'WHAMI provides a verified position estimate based on multiple device '
                          'sensors and offline data sources. It is intended as a navigation '
                          'confidence and redundancy layer. It should not be used as the sole '
                          'source of navigation in safety-critical marine, aviation, rescue, or '
                          'vehicle operations unless certified for that specific use case.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: const [
                      Text(
                        'WHAMI v0.1.0 — Prototype',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '"GPS is only one witness."',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustFormulaCard extends StatelessWidget {
  final Map<String, dynamic> breakdown;

  const _TrustFormulaCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate, color: AppColors.headerBg, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Trust Score Breakdown',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.forTrust(breakdown['finalScore'] as int)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.forTrust(breakdown['finalScore'] as int),
                    ),
                  ),
                  child: Text(
                    '${breakdown['finalScore']}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.forTrust(breakdown['finalScore'] as int),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Trust = 0.45×Landmark + 0.20×GPS + 0.15×Magnetic + 0.10×IMU + 0.10×Sky',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            _FormulaRow(
              label: 'Landmark Match',
              value: breakdown['landmarkMatch'] as int,
              weight: '× 0.45',
              color: AppColors.landmark,
            ),
            _FormulaRow(
              label: 'GPS Confidence',
              value: breakdown['gpsConfidence'] as int,
              weight: '× 0.20',
              color: AppColors.gps,
            ),
            _FormulaRow(
              label: 'Magnetic Fit',
              value: breakdown['magneticFit'] as int,
              weight: '× 0.15',
              color: AppColors.magnetic,
            ),
            _FormulaRow(
              label: 'IMU Path',
              value: breakdown['imuPath'] as int,
              weight: '× 0.10',
              color: AppColors.imu,
            ),
            _FormulaRow(
              label: 'Sky Stability',
              value: breakdown['skyStability'] as int,
              weight: '× 0.10',
              color: AppColors.sextant,
            ),
            const Divider(height: 20),
            const Text(
              'WHAMI gives higher weight to physical-world anchors like landmark/seamap. '
              'GPS is useful but never treated as absolute authority.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormulaRow extends StatelessWidget {
  final String label;
  final int value;
  final String weight;
  final Color color;

  const _FormulaRow({
    required this.label,
    required this.value,
    required this.weight,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
          Text(
            weight,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value / 100,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '$value%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.forTrust(value),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
