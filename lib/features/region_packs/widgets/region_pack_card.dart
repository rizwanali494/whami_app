import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../core/widgets/whami_chrome.dart';
import '../../../data/models/region_pack.dart';
import '../../../data/repositories/whami_repository.dart';

class RegionPackCard extends StatelessWidget {
  final RegionPack pack;
  final WhamiRepository repository;

  const RegionPackCard({
    super.key,
    required this.pack,
    required this.repository,
  });

  Color _typeColor(String type) {
    switch (type) {
      case 'Marine':
        return AppColors.gps;
      case 'Lake':
        return AppColors.sextant;
      case 'Hiking':
        return AppColors.magnetic;
      case 'Urban':
        return AppColors.imu;
      case 'Aviation':
        return WhamiAviation.cyan;
      case 'River':
        return const Color(0xFF00ACC1);
      case 'Island':
        return const Color(0xFFFF7043);
      case 'Desert':
        return const Color(0xFFF9A825);
      case 'Arctic':
        return const Color(0xFF5C6BC0);
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildActionArea(bool isActive, Color typeColor) {
    final isFailed = pack.downloadStage.startsWith('Failed:');
    if (pack.status == 'downloading') {
      final stage = pack.downloadStage.isEmpty
          ? 'Downloading…'
          : pack.downloadStage;
      final pct = (pack.downloadProgress * 100).clamp(0, 100).round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stage,
                  style: WhamiAviation.body(color: WhamiAviation.lightMuted),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: WhamiAviation.lightInk,
                  fontSize: 12,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: WhamiAviation.lightMuted,
                onPressed: () => repository.cancelDownload(pack.id),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pack.downloadProgress,
              backgroundColor: WhamiAviation.lightBorder,
              valueColor: AlwaysStoppedAnimation<Color>(typeColor),
              minHeight: 5,
            ),
          ),
        ],
      );
    }

    if (pack.status == 'available') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                pack.downloadStage,
                style: const TextStyle(fontSize: 12, color: WhamiAviation.danger),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => repository.startDownload(pack.id),
              icon: Icon(Icons.download_rounded, size: 18, color: typeColor),
              label: Text(
                pack.isDemoPack
                    ? (isFailed ? 'Retry install' : 'Install demo pack')
                    : (isFailed
                        ? 'Retry download'
                        : 'Download · ${pack.size}'),
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: typeColor.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final activatingThis = repository.activatingPackId == pack.id;
    final busy =
        repository.isActivatingPack || repository.isDeactivatingPack;

    if (activatingThis || (isActive && repository.isDeactivatingPack)) {
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton.icon(
          onPressed: null,
          icon: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: typeColor),
          ),
          label: Text(
            activatingThis ? 'Activating…' : 'Deactivating…',
            style: TextStyle(color: typeColor, fontWeight: FontWeight.w800),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: typeColor.withValues(alpha: 0.55)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 46,
      child: isActive
          ? FilledButton.icon(
              onPressed: busy ? null : () => repository.deactivateRegionPack(),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text(
                'Deactivate',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: WhamiAviation.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => repository.activateRegionPack(pack.id),
              icon: const Icon(Icons.bolt_rounded, size: 18),
              label: const Text(
                'Activate',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: WhamiAviation.navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = repository.activePackId == pack.id;
    final typeColor = _typeColor(pack.type);
    final pad = WhamiLayout.pagePad(context);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
      decoration: WhamiAviation.lightCard().copyWith(
        border: Border.all(
          color: isActive
              ? WhamiAviation.success.withValues(alpha: 0.55)
              : WhamiAviation.lightBorder,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(WhamiLayout.isTablet(context) ? 18 : 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: typeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    pack.type.toUpperCase(),
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (pack.isDemoPack)
                  const WhamiStatusPill(
                    label: 'Demo landmarks',
                    color: WhamiAviation.amber,
                  ),
                if (!pack.isDemoPack && pack.hasOfflineMapTiles) ...[
                  const SizedBox(width: 6),
                  const WhamiStatusPill(
                    label: 'Offline tiles',
                    color: WhamiAviation.cyanDim,
                  ),
                ],
                const Spacer(),
                if (isActive)
                  const WhamiStatusPill(
                    label: 'Active',
                    color: WhamiAviation.success,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              pack.name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: WhamiAviation.lightInk,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pack.location,
              style: WhamiAviation.body(color: WhamiAviation.lightMuted),
            ),
            const SizedBox(height: 10),
            Text(
              pack.coverageSummary,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: WhamiAviation.lightMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ...pack.includedData.map((d) => _DataChip(label: d)),
                _DataChip(label: pack.size),
                _DataChip(label: 'Trust ${pack.trustScore}%'),
              ],
            ),
            if (pack.isDemoPack) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: WhamiAviation.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: WhamiAviation.amber.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'No offline map tiles in this pack. WHAMI uses the street/'
                  'satellite basemap (online or cached) plus bundled landmarks '
                  'around Tocumwal (YTOC).',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: WhamiAviation.lightInk,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _buildActionArea(isActive, typeColor),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WhamiAviation.lightWash,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WhamiAviation.lightBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: WhamiAviation.lightMuted,
        ),
      ),
    );
  }
}
