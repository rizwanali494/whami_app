import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_version.dart';
import '../../core/constants/connectivity_status.dart';
import '../../core/preferences/app_preferences.dart';
import '../../core/trust/trust_summary.dart';
import '../../core/widgets/status_panel.dart';
import '../../data/repositories/whami_repository.dart';

class SettingsScreen extends StatefulWidget {
  final WhamiRepository repository;

  const SettingsScreen({super.key, required this.repository});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  Future<void> _showStorageSheet() async {
    final packs = widget.repository.packs
        .where((p) => p.status == 'downloaded')
        .toList();
    final totalBytes = packs.fold<int>(0, (sum, p) {
      final raw = p.size.replaceAll(RegExp(r'[^0-9.]'), '');
      final n = double.tryParse(raw) ?? 0;
      if (p.size.toLowerCase().contains('gb')) {
        return sum + (n * 1024 * 1024 * 1024).round();
      }
      if (p.size.toLowerCase().contains('mb')) {
        return sum + (n * 1024 * 1024).round();
      }
      return sum + n.round();
    });

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Offline pack storage',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                packs.isEmpty
                    ? 'No packs downloaded yet. Open Offline to add region data.'
                    : '${packs.length} pack(s) installed · ~${_formatBytes(totalBytes)} used',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (packs.isEmpty)
                StatusPanel.empty(
                  title: 'Nothing stored offline',
                  message: 'Downloaded region packs appear here with size estimates.',
                  actionLabel: 'Go to Offline',
                  onAction: () {
                    Navigator.pop(ctx);
                    context.go('/packs');
                  },
                )
              else
                ...packs.map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(p.name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(p.size, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/packs');
                  },
                  child: const Text('Manage offline packs'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPrivacySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Position fusion runs on-device. Sensor streams and region packs '
                'stay local unless you choose to download packs from the catalog CDN.',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 12),
              const Text(
                'Camera frames used for Verify stay on the device and are not uploaded.',
                style: TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.repository.getTrustBreakdown();
    final prefs = context.watch<AppPreferences>();
    final summary = TrustSummary.fromOpinions(
      trustScore: breakdown['finalScore'] as int? ?? widget.repository.trustScore,
      opinions: widget.repository.getPositionOpinions(),
      isTracking: widget.repository.isTracking,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: const Text('Diagnostics & Settings'),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _TrustPlainCard(summary: summary, breakdown: breakdown),
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Diagnostics'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.flight, color: AppColors.whami),
                        title: const Text(
                          'WHAMI-Air Research',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: const Text(
                          'Advisory GNSS-denied trust · WMM · flight recorder',
                          style: TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/air'),
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.sensors, color: AppColors.imu),
                        title: const Text(
                          'Sensors',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: const Text(
                          'GPS, magnetometer, IMU, barometer, camera, sky',
                          style: TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/sensors'),
                      ),
                      const Divider(height: 1, indent: 16),
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.wb_sunny_outlined,
                          color: AppColors.whami,
                        ),
                        title: const Text(
                          'Outdoor / high-contrast mode',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: const Text(
                          'Dark map chrome for bright sunlight',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: prefs.outdoorMode,
                        onChanged: prefs.setOutdoorMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Settings'),
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.wifi, color: AppColors.gps),
                        title: const Text(
                          'Connectivity Mode',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: Text(
                          widget.repository.connectivityMode ==
                                  ConnectivityMode.online
                              ? 'Online (All sources active)'
                              : widget.repository.connectivityMode ==
                                      ConnectivityMode.offline
                                  ? 'Offline (Local pack verified)'
                                  : 'Limited (GPS only, pack disabled)',
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: DropdownButton<ConnectivityMode>(
                          value: widget.repository.connectivityMode,
                          underline: const SizedBox.shrink(),
                          onChanged: (mode) {
                            if (mode != null) {
                              widget.repository.connectivityMode = mode;
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                              value: ConnectivityMode.online,
                              child: Text('Online'),
                            ),
                            DropdownMenuItem(
                              value: ConnectivityMode.offline,
                              child: Text('Offline'),
                            ),
                            DropdownMenuItem(
                              value: ConnectivityMode.limited,
                              child: Text('Limited'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 16),
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.straighten,
                          color: AppColors.imu,
                        ),
                        title: const Text('Units', style: TextStyle(fontSize: 15)),
                        subtitle: Text(
                          prefs.useMetric ? 'Metric (m, km)' : 'Imperial (ft, mi)',
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: prefs.useMetric,
                        onChanged: prefs.setUseMetric,
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(
                          Icons.storage,
                          color: AppColors.sextant,
                        ),
                        title: const Text(
                          'Offline Pack Storage',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: const Text(
                          'View downloaded packs and usage',
                          style: TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showStorageSheet,
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(
                          Icons.privacy_tip_outlined,
                          color: AppColors.magnetic,
                        ),
                        title: const Text(
                          'Privacy',
                          style: TextStyle(fontSize: 15),
                        ),
                        subtitle: const Text(
                          'On-device fusion · optional CDN downloads',
                          style: TextStyle(fontSize: 13),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showPrivacySheet,
                      ),
                      const Divider(height: 1, indent: 16),
                      ListTile(
                        leading: const Icon(Icons.school_outlined),
                        title: const Text(
                          'Show onboarding again',
                          style: TextStyle(fontSize: 15),
                        ),
                        onTap: () async {
                          await prefs.setOnboardingSeen(false);
                          if (context.mounted) context.go('/onboarding');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Disclaimer'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.alertWarning,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.trustMediumDark.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text(
                      'WHAMI provides a verified position estimate based on multiple device '
                      'sensors and offline data sources. It is a navigation aid — not the sole '
                      'source of navigation for safety-critical operations unless certified.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Column(
                    children: [
                      Text(
                        AppVersion.label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '"GPS is only one witness."',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _TrustPlainCard extends StatelessWidget {
  final TrustSummary summary;
  final Map<String, dynamic> breakdown;

  const _TrustPlainCard({required this.summary, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(summary.level.icon, color: summary.level.color, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.headline,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: summary.level.color,
                    ),
                  ),
                ),
                Text(
                  '${summary.score}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: summary.level.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary.subtitle, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(summary.explanation, style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 6),
            Text(
              'What to do: ${summary.action}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Trust = 0.45×Landmark + 0.20×GPS + 0.15×Magnetic + 0.10×IMU + 0.10×Sky',
              style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 10),
            _MiniRow('Landmark', breakdown['landmarkMatch'] as int? ?? 0, AppColors.landmark),
            _MiniRow('GPS', breakdown['gpsConfidence'] as int? ?? 0, AppColors.gps),
            _MiniRow('Magnetic', breakdown['magneticFit'] as int? ?? 0, AppColors.magnetic),
            _MiniRow('IMU', breakdown['imuPath'] as int? ?? 0, AppColors.imu),
            _MiniRow('Sky', breakdown['skyStability'] as int? ?? 0, AppColors.sextant),
          ],
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MiniRow(this.label, this.value, this.color);

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
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '$value%',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.forTrust(value),
            ),
          ),
        ],
      ),
    );
  }
}
