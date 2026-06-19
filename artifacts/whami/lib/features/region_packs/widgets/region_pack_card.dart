import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/region_pack.dart';
import '../../../data/repositories/whami_mock_repository.dart';
import 'pack_file_explorer.dart';

class RegionPackCard extends StatefulWidget {
  final RegionPack pack;
  final WhamiMockRepository repository;

  const RegionPackCard({
    super.key,
    required this.pack,
    required this.repository,
  });

  @override
  State<RegionPackCard> createState() => _RegionPackCardState();
}

class _RegionPackCardState extends State<RegionPackCard> {
  bool _verified = false;

  Color _typeColor(String type) {
    switch (type) {
      case 'Marine': return AppColors.gps;
      case 'Lake': return AppColors.sextant;
      case 'Hiking': return AppColors.magnetic;
      case 'Urban': return AppColors.imu;
      default: return AppColors.textSecondary;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'downloaded': return AppColors.trustHigh;
      case 'downloading': return AppColors.gps;
      case 'available': return AppColors.textSecondary;
      case 'update_needed': return AppColors.alertWarningBorder;
      default: return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'downloaded': return 'Downloaded';
      case 'downloading': return 'Downloading...';
      case 'available': return 'Available';
      case 'update_needed': return 'Update Needed';
      default: return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'downloaded': return Icons.check_circle;
      case 'downloading': return Icons.downloading;
      case 'available': return Icons.cloud_download_outlined;
      case 'update_needed': return Icons.update;
      default: return Icons.help_outline;
    }
  }

  void _onVerify() => setState(() => _verified = true);

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    final typeColor = _typeColor(pack.type);
    final statusColor = _statusColor(pack.status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    pack.type.toUpperCase(),
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        pack.location,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _statusIcon(pack.status),
                          color: statusColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _statusLabel(pack.status),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      pack.size,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Included data chips
            if (!pack.isDownloading) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: pack.includedData
                    .map((d) => _DataChip(label: d))
                    .toList(),
              ),
              const SizedBox(height: 10),
            ],

            // Staged download progress
            if (pack.isDownloading) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: AppColors.gps,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pack.downloadStage,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${(pack.downloadProgress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gps,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pack.downloadProgress,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gps),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Est. time remaining: ${((1.0 - pack.downloadProgress) * 6).ceil()}s',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => widget.repository.cancelDownload(pack.id),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.trustLow,
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else ...[
              // Trust score bar
              Row(
                children: [
                  const Text(
                    'Pack Trust Score',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${pack.trustScore}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.forTrust(pack.trustScore),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pack.trustScore / 100,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.forTrust(pack.trustScore)),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Buttons
            Row(
              children: [
                if (pack.status != 'downloaded' && !pack.isDownloading)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => widget.repository.startDownload(pack.id),
                      icon: const Icon(Icons.cloud_download, size: 16),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  )
                else if (pack.status == 'downloaded') ...[
                  if (widget.repository.activePackId == pack.id)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.check_circle, color: Colors.white, size: 16),
                        label: const Text('Active Pack'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.trustHigh,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.trustHigh,
                          disabledForegroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => widget.repository.activateRegionPack(pack.id),
                        icon: const Icon(Icons.bolt, size: 16),
                        label: const Text('Activate Pack'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.headerBg,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Pack?'),
                          content: Text('Are you sure you want to remove ${pack.name} from offline storage?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                widget.repository.deleteRegionPack(pack.id);
                                Navigator.pop(ctx);
                              },
                              style: TextButton.styleFrom(foregroundColor: AppColors.trustLow),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, color: AppColors.trustLow),
                    tooltip: 'Delete Region Pack',
                  ),
                ],
                if (!pack.isDownloading) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PackDetailPage(pack: pack, repository: widget.repository),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Details'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DataChip extends StatelessWidget {
  final String label;

  const _DataChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
      ),
    );
  }
}

class _PackDetailPage extends StatelessWidget {
  final RegionPack pack;
  final WhamiMockRepository repository;

  const _PackDetailPage({required this.pack, required this.repository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        title: Text(
          pack.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        leading: const BackButton(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pack metadata card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow(label: 'Location', value: pack.location),
                  _DetailRow(label: 'Type', value: pack.type),
                  _DetailRow(label: 'Size', value: pack.size),
                  _DetailRow(label: 'Last Updated', value: pack.lastUpdated),
                  _DetailRow(label: 'Trust Score', value: '${pack.trustScore}%'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // File Explorer
          PackFileExplorer(pack: pack, repository: repository),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
