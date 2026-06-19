import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/region_pack.dart';
import '../../../data/repositories/whami_mock_repository.dart';

class PackFileExplorer extends StatefulWidget {
  final RegionPack pack;
  final WhamiMockRepository repository;

  const PackFileExplorer({
    super.key,
    required this.pack,
    required this.repository,
  });

  @override
  State<PackFileExplorer> createState() => _PackFileExplorerState();
}

class _PackFileExplorerState extends State<PackFileExplorer> {
  final Set<String> _expandedFolders = {};

  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final fileSizes = pack.fileSizes;

    // Define mock folder tree
    final folders = [
      _FolderItem(
        path: '/maps',
        name: 'Map Tiles',
        desc: 'Offline base map vector tiles',
        sizeKey: 'maps',
        icon: Icons.map_outlined,
        type: 'maps',
      ),
      _FolderItem(
        path: '/marine',
        name: 'Sea Charts',
        desc: 'Offline seamaps and safety channels',
        sizeKey: 'marine',
        icon: Icons.water_outlined,
        type: 'marine',
      ),
      _FolderItem(
        path: '/landmarks',
        name: 'Landmark Coordinates',
        desc: 'Visual physical landmark targets',
        sizeKey: 'landmarks',
        icon: Icons.location_on_outlined,
        type: 'landmarks',
      ),
      _FolderItem(
        path: '/magnetic',
        name: 'Magnetic Grid Readings',
        desc: 'Offline magnetic anomaly reference grid',
        sizeKey: 'magnetic',
        icon: Icons.explore_outlined,
        type: 'magnetic',
      ),
      _FolderItem(
        path: '/celestial',
        name: 'Celestial Tables',
        desc: 'Sun, moon, and star alignment tables',
        sizeKey: 'celestial',
        icon: Icons.wb_sunny_outlined,
        type: 'celestial',
      ),
      if (fileSizes.containsKey('imu'))
        _FolderItem(
          path: '/imu',
          name: 'IMU Path Templates',
          desc: 'Motion prediction profiles',
          sizeKey: 'imu',
          icon: Icons.directions_walk_outlined,
          type: 'imu',
        ),
      if (fileSizes.containsKey('trust'))
        _FolderItem(
          path: '/trust',
          name: 'Route Trust History',
          desc: 'Historical sensor-drift patterns',
          sizeKey: 'trust',
          icon: Icons.shield_outlined,
          type: 'trust',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Storage Usage Breakdown Chart
        _buildStorageUsageChart(folders, fileSizes),
        const SizedBox(height: 16),

        const Text(
          'LOCAL FILE SYSTEM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),

        // Folder tree
        ...folders.map((folder) {
          final hasData = fileSizes.containsKey(folder.sizeKey);
          final isExpanded = _expandedFolders.contains(folder.path);
          final sizeStr = fileSizes[folder.sizeKey] ?? 'Not downloaded';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  onTap: hasData ? () => _toggleFolder(folder.path) : null,
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hasData
                          ? AppColors.gps.withOpacity(0.08)
                          : AppColors.divider,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      folder.icon,
                      color: hasData ? AppColors.gps : AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        folder.path,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: hasData ? AppColors.textPrimary : AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (hasData)
                        const Icon(
                          Icons.verified_user,
                          color: AppColors.trustHigh,
                          size: 12,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${folder.name} · $sizeStr',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  trailing: hasData
                      ? Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          color: AppColors.textSecondary,
                          size: 18,
                        )
                      : const Icon(
                          Icons.lock_outline,
                          color: AppColors.textSecondary,
                          size: 14,
                        ),
                ),
                if (isExpanded && hasData) ...[
                  const Divider(height: 1, color: AppColors.divider),
                  _buildFolderContents(folder.type),
                ]
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStorageUsageChart(List<_FolderItem> folders, Map<String, String> fileSizes) {
    // Parse size strings (e.g. "98.4 MB (847 tiles)") to approximate doubles
    double total = 0.0;
    final List<(String, double, Color)> segments = [];
    final colors = [
      AppColors.gps,
      AppColors.sextant,
      AppColors.whami,
      AppColors.magnetic,
      AppColors.imu,
      Colors.blueGrey,
      Colors.indigo,
    ];

    int index = 0;
    for (final folder in folders) {
      final sizeStr = fileSizes[folder.sizeKey];
      if (sizeStr != null) {
        final double sizeVal = _parseMegabytes(sizeStr);
        total += sizeVal;
        segments.add((folder.name, sizeVal, colors[index % colors.length]));
        index++;
      }
    }

    if (total == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Storage Allocation',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  '${total.toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.gps),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Custom segment bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: segments.map((seg) {
                    final percentage = seg.$2 / total;
                    return Expanded(
                      flex: (percentage * 100).round().clamp(1, 100),
                      child: Container(
                        color: seg.$3,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: segments.map((seg) {
                final pct = (seg.$2 / total * 100).toStringAsFixed(0);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: seg.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${seg.$1} ($pct%)',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  double _parseMegabytes(String sizeStr) {
    try {
      final parts = sizeStr.split(' ');
      if (parts.isNotEmpty) {
        return double.parse(parts[0]);
      }
    } catch (_) {}
    return 10.0;
  }

  Widget _buildFolderContents(String type) {
    if (type == 'landmarks') {
      final landmarks = widget.repository.getLandmarks();
      return Container(
        color: AppColors.background.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: landmarks.map((landmark) {
            return ListTile(
              dense: true,
              leading: Icon(
                landmark.saved ? Icons.location_on : Icons.location_on_outlined,
                color: landmark.saved ? AppColors.magnetic : AppColors.textSecondary,
                size: 16,
              ),
              title: Text(
                landmark.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              subtitle: Text(
                'Lat: ${landmark.latitude.toStringAsFixed(4)} · Lng: ${landmark.longitude.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
              trailing: TextButton.icon(
                onPressed: () {
                  // Center map in repository
                  widget.repository.centerMapOn(landmark.latitude, landmark.longitude);
                  // Navigate back to the Map branch (index 0) in shell
                  // We can pop the detail screen and jump to map.
                  // Since GoRouter index stack is at /packs, we go to /map.
                  Navigator.pop(context); // Close detail dialog/screen
                  context.go('/map');
                },
                icon: const Icon(Icons.map, size: 12),
                label: const Text('Show', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    // Default metadata contents for other folders
    String contentText = '';
    switch (type) {
      case 'maps':
        contentText = '• Contains 847 local vector tiles (z8 to z15)\n• Extent: bounding box covering San Francisco Bay\n• Format: Mapbox Vector Tiles (.pbf)';
        break;
      case 'marine':
        contentText = '• Channels and sea lanes vector coordinates\n• Nautical depths contour lines (meters)\n• Local navigational markers and buoy list';
        break;
      case 'magnetic':
        contentText = '• Magnetic baseline grid covering 37.7°N to 37.9°N\n• Grid density: 2500 coordinates\n• Calculated from NOAA WMM2025 epoch';
        break;
      case 'celestial':
        contentText = '• Star & solar ephemerides tables for 2026-2027\n• Pre-computed celestial heights for sextant validation\n• Lunar drift offset coefficients';
        break;
      case 'imu':
        contentText = '• Local sea current drift models\n• Vessel movement pattern templates\n• Inertial navigation noise-filtering configurations';
        break;
      case 'trust':
        contentText = '• Historical route performance metrics\n• GPS variance signatures in SF Bay area\n• Local signal reflection (multipath) zones map';
        break;
      default:
        contentText = 'Verified offline database files.';
    }

    return Container(
      width: double.infinity,
      color: AppColors.background.withOpacity(0.5),
      padding: const EdgeInsets.all(12),
      child: Text(
        contentText,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),
    );
  }
}

class _FolderItem {
  final String path;
  final String name;
  final String desc;
  final String sizeKey;
  final IconData icon;
  final String type;

  _FolderItem({
    required this.path,
    required this.name,
    required this.desc,
    required this.sizeKey,
    required this.icon,
    required this.type,
  });
}
