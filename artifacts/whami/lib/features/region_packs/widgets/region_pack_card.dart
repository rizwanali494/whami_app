import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    final isActive = repository.activePackId == pack.id;
    final typeColor = _typeColor(pack.type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: AppColors.trustHigh, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeColor.withValues(alpha: 0.4)),
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
                const SizedBox(width: 10),
                // Name + location
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
                      const SizedBox(height: 2),
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
                // Active indicator badge
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.trustHigh.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.trustHigh.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.trustHigh,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: AppColors.trustHigh,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Included data chips ──────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: pack.includedData
                  .map((d) => _DataChip(label: d))
                  .toList(),
            ),

            const SizedBox(height: 12),

            // ── Trust score bar ──────────────────────────────────────────
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
                  pack.size,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
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
                  AppColors.forTrust(pack.trustScore),
                ),
                minHeight: 4,
              ),
            ),

            const SizedBox(height: 14),

            // ── Activate / Deactivate button ─────────────────────────────
            SizedBox(
              width: double.infinity,
              child: isActive
                  ? ElevatedButton.icon(
                      onPressed: () => repository.deactivateRegionPack(),
                      icon: const Icon(Icons.radio_button_checked, size: 16),
                      label: const Text('Deactivate Pack'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.trustHigh,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => repository.activateRegionPack(pack.id),
                      icon: Icon(Icons.bolt, size: 16, color: typeColor),
                      label: Text(
                        'Activate Pack',
                        style: TextStyle(color: typeColor),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        side: BorderSide(
                          color: typeColor.withValues(alpha: 0.6),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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
