import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_mock_repository.dart';
import 'widgets/region_pack_card.dart';

class RegionPackScreen extends StatefulWidget {
  final WhamiMockRepository repository;

  const RegionPackScreen({super.key, required this.repository});

  @override
  State<RegionPackScreen> createState() => _RegionPackScreenState();
}

class _RegionPackScreenState extends State<RegionPackScreen> {
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
    final packs = widget.repository.getRegionPacks();
    final downloaded = packs.where((p) => p.status == 'downloaded').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.headerBg,
            pinned: true,
            title: const Text(
              'Region Packs',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  backgroundColor: AppColors.trustHigh.withOpacity(0.15),
                  label: Text(
                    '$downloaded Downloaded',
                    style: TextStyle(
                      color: AppColors.trustHigh,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Moat explanation
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.headerBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock, color: AppColors.whami, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "WHAMI's Data Moat",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Region packs include offline maps, landmarks, magnetic baselines, '
                                'celestial tables, and route trust history — all verified and stored '
                                'locally. No internet required during navigation.',
                                style: TextStyle(
                                  color: Color(0xFF90A4AE),
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Available Packs',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                ...packs.map(
                  (pack) => RegionPackCard(
                    key: ValueKey(pack.id),
                    pack: widget.repository.getRegionPackById(pack.id)!,
                    repository: widget.repository,
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
