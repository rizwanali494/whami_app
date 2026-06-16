import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/region_pack.dart';

class RegionPackCard extends StatefulWidget {
  final RegionPack pack;
  final VoidCallback onStatusChanged;

  const RegionPackCard({
    super.key,
    required this.pack,
    required this.onStatusChanged,
  });

  @override
  State<RegionPackCard> createState() => _RegionPackCardState();
}

class _RegionPackCardState extends State<RegionPackCard> {
  bool _downloading = false;
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
      case 'available': return AppColors.textSecondary;
      case 'update_needed': return AppColors.alertWarningBorder;
      default: return AppColors.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'downloaded': return 'Downloaded';
      case 'available': return 'Available';
      case 'update_needed': return 'Update Needed';
      default: return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'downloaded': return Icons.check_circle;
      case 'available': return Icons.cloud_download_outlined;
      case 'update_needed': return Icons.update;
      default: return Icons.help_outline;
    }
  }

  Future<void> _onDownload() async {
    setState(() => _downloading = true);
    await Future.delayed(const Duration(seconds: 2));
    widget.onStatusChanged();
    if (mounted) setState(() => _downloading = false);
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
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: pack.includedData
                  .map((d) => _DataChip(label: d))
                  .toList(),
            ),
            const SizedBox(height: 10),

            // Trust score
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

            // Buttons
            Row(
              children: [
                if (pack.status != 'downloaded')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _downloading ? null : _onDownload,
                      icon: _downloading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_download, size: 16),
                      label: Text(_downloading ? 'Downloading...' : 'Download'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onVerify,
                      icon: Icon(
                        _verified ? Icons.verified : Icons.fact_check_outlined,
                        size: 16,
                        color: _verified ? AppColors.trustHigh : null,
                      ),
                      label: Text(_verified ? 'Verified' : 'Verify'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _verified ? AppColors.trustHigh : null,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PackDetailPage(pack: pack),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Details'),
                ),
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

  const _PackDetailPage({required this.pack});

  @override
  Widget build(BuildContext context) {
    final folders = [
      ('/maps', 'Land maps & vector tiles', Icons.map),
      ('/marine', 'Marine & lake data layers', Icons.water),
      ('/landmarks', 'Visual landmark database', Icons.location_on),
      ('/magnetic', 'Magnetic field baseline grid', Icons.explore),
      ('/celestial', 'Celestial tables & star catalog', Icons.wb_sunny),
      ('/imu', 'IMU path templates', Icons.directions_walk),
      ('/trust', 'Route trust history', Icons.shield),
    ];

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
          // Pack info card
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
          const SizedBox(height: 12),
          const Text(
            'Pack Contents',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...folders.map((f) {
            final (path, desc, icon) = f;
            final hasData = pack.includedData.any((d) =>
                d.toLowerCase().contains(path.substring(1)));
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: hasData
                        ? AppColors.trustHigh.withOpacity(0.12)
                        : AppColors.divider,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: hasData ? AppColors.trustHigh : Colors.grey,
                    size: 18,
                  ),
                ),
                title: Text(
                  path,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: hasData ? AppColors.textPrimary : Colors.grey,
                  ),
                ),
                subtitle: Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: hasData ? AppColors.textSecondary : Colors.grey,
                  ),
                ),
                trailing: Icon(
                  hasData ? Icons.check_circle : Icons.remove_circle_outline,
                  color: hasData ? AppColors.trustHigh : Colors.grey,
                  size: 18,
                ),
              ),
            );
          }),
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
