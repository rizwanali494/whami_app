import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../constants/connectivity_status.dart';
import '../../data/repositories/whami_repository.dart';

class OfflineBanner extends StatelessWidget {
  final WhamiRepository repository;

  const OfflineBanner({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final mode = repository.connectivityMode;
        final activePack = repository.getRegionPackById(repository.activePackId);
        final activePackName = activePack?.name ?? 'No Pack';
        final hasPack = activePack != null && activePack.status == 'downloaded';

        Color bg;
        Color text;
        String message;
        IconData icon;

        switch (mode) {
          case ConnectivityMode.online:
            bg = AppColors.trustHigh.withValues(alpha: 0.9);
            text = Colors.white;
            message = 'Online · $activePackName Loaded · All Sources Active';
            icon = Icons.wifi;
            break;
          case ConnectivityMode.offline:
            bg = AppColors.whami;
            text = AppColors.headerBg;
            message = 'OFFLINE · $activePackName Active · No Internet Needed';
            icon = Icons.wifi_off_rounded;
            break;
          case ConnectivityMode.limited:
            bg = AppColors.trustLow;
            text = Colors.white;
            message = 'LIMITED · GPS Only · Download Region Pack For Full Trust';
            icon = Icons.signal_cellular_connected_no_internet_4_bar_rounded;
            break;
        }

        return InkWell(
          onTap: () => _showStatusDetails(context, mode, hasPack),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                top: BorderSide(color: bg.withValues(alpha: 0.6), width: 0.5),
              ),
            ),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 13, color: text),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: text,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_up, size: 13, color: text.withValues(alpha: 0.7)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStatusDetails(BuildContext context, ConnectivityMode mode, bool hasPack) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.headerBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.whami, size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'WHAMI Engine Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                const SizedBox(height: 8),
                _buildStatusRow(
                  context,
                  title: 'GPS Witness Layer',
                  subtitle: 'Satellite positioning coordinates status.',
                  isActive: true,
                  badgeText: 'Active',
                  badgeColor: AppColors.gps,
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  context,
                  title: 'Physical Landmarks',
                  subtitle: 'Camera/visual identification landmarks.',
                  isActive: mode != ConnectivityMode.limited && hasPack,
                  badgeText: mode == ConnectivityMode.limited ? 'Offline' : (hasPack ? 'Offline Ready' : 'Need Pack'),
                  badgeColor: mode != ConnectivityMode.limited && hasPack ? AppColors.trustHigh : AppColors.trustLow,
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  context,
                  title: 'Magnetic Baseline',
                  subtitle: 'Geomagnetic anomaly grid cross-checks.',
                  isActive: mode != ConnectivityMode.limited && hasPack,
                  badgeText: mode == ConnectivityMode.limited ? 'Offline' : (hasPack ? 'Offline Ready' : 'Need Pack'),
                  badgeColor: mode != ConnectivityMode.limited && hasPack ? AppColors.trustHigh : AppColors.trustLow,
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  context,
                  title: 'Celestial Alignment',
                  subtitle: 'Sun/stars azimuth computations.',
                  isActive: mode != ConnectivityMode.limited && hasPack,
                  badgeText: mode == ConnectivityMode.limited ? 'Offline' : (hasPack ? 'Offline Ready' : 'Need Pack'),
                  badgeColor: mode != ConnectivityMode.limited && hasPack ? AppColors.trustHigh : AppColors.trustLow,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go('/packs');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.whami,
                      foregroundColor: AppColors.headerBg,
                    ),
                    child: const Text('Manage Region Packs'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isActive,
    required String badgeText,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
