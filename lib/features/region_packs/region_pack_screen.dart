import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/whami_aviation.dart';
import '../../core/widgets/whami_chrome.dart';
import '../../data/models/region_pack.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/region_pack_card.dart';

class RegionPackScreen extends StatefulWidget {
  final WhamiRepository repository;

  const RegionPackScreen({super.key, required this.repository});

  @override
  State<RegionPackScreen> createState() => _RegionPackScreenState();
}

class _RegionPackScreenState extends State<RegionPackScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _selectedType = 'All';

  static const _typeFilters = [
    'All',
    'Aviation',
    'Urban',
    'Marine',
    'Hiking',
    'Lake',
    'River',
    'Island',
    'Desert',
    'Arctic',
  ];

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_refresh);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    widget.repository.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  List<RegionPack> _filteredPacks(List<RegionPack> packs) {
    return packs.where((p) {
      final matchesType = _selectedType == 'All' || p.type == _selectedType;
      if (_query.isEmpty) return matchesType;
      return matchesType &&
          (p.name.toLowerCase().contains(_query) ||
              p.location.toLowerCase().contains(_query) ||
              p.type.toLowerCase().contains(_query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final packs = widget.repository.getRegionPacks();
    final filtered = _filteredPacks(packs);

    // Move active pack to top of list
    final activeId = widget.repository.activePackId;
    final activePack = widget.repository.getRegionPackById(activeId);
    final activeIndex = filtered.indexWhere((p) => p.id == activeId);
    if (activeIndex > 0) {
      final ap = filtered.removeAt(activeIndex);
      filtered.insert(0, ap);
    }

    final pad = WhamiLayout.pagePad(context);

    return Scaffold(
      backgroundColor: WhamiAviation.lightWash,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: WhamiAviation.navy,
            pinned: true,
            expandedHeight: 72,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: WhamiAviation.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'Regional packs',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            actions: [
              if (activePack != null)
                Padding(
                  padding: EdgeInsets.only(right: pad),
                  child: Center(
                    child: WhamiStatusPill(
                      label: activePack.isDemoPack
                          ? 'Demo · ${activePack.name}'
                          : activePack.name,
                      color: WhamiAviation.success,
                    ),
                  ),
                ),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.repository.missionPacks.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ONE-TAP MISSIONS',
                          style: TextStyle(
                            color: WhamiAviation.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 108,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.repository.missionPacks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, i) {
                              final p = widget.repository.missionPacks[i];
                              return InkWell(
                                onTap: () =>
                                    widget.repository.launchMissionPack(p),
                                borderRadius: BorderRadius.circular(14),
                                child: Ink(
                                  width: 168,
                                  padding: const EdgeInsets.all(12),
                                  decoration: WhamiAviation.glassPanel(
                                    radius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.missionProfile.toUpperCase(),
                                        style: WhamiAviation.overline(
                                          color: WhamiAviation.cyan,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        p.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        p.status == 'downloaded' ||
                                                p.checksum == 'bundled-demo'
                                            ? 'TAP TO LAUNCH'
                                            : 'TAP TO DOWNLOAD',
                                        style: WhamiAviation.overline(
                                          color: WhamiAviation.amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: WhamiAviation.glassPanel(
                      radius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.layers_outlined,
                            color: WhamiAviation.cyan, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Offline coverage',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Full packs ship offline map tiles + landmarks. '
                                'Demo packs provide landmarks only — the basemap '
                                'stays online or from tile cache.',
                                style: TextStyle(
                                  color: WhamiAviation.textSecondary,
                                  fontSize: 12,
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

                // ── Search bar ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search regions, locations, types…',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.gps,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Type filter chips ────────────────────────────────────────
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    itemCount: _typeFilters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final type = _typeFilters[i];
                      final active = _selectedType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedType = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: active ? AppColors.headerBg : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: active
                                  ? AppColors.headerBg
                                  : AppColors.divider,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            type,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: active
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Results count ────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} pack${filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (_query.isNotEmpty || _selectedType != 'All') ...[
                        const Text(
                          ' · ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _selectedType = 'All';
                            });
                          },
                          child: const Text(
                            'Clear filters',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.gps,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Pack list ──────────────────────────────────────────────────────
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(
                      Icons.travel_explore,
                      size: 48,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No packs match your search',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((ctx, i) {
                final pack = filtered[i];
                return RegionPackCard(
                  key: ValueKey(pack.id),
                  pack: widget.repository.getRegionPackById(pack.id)!,
                  repository: widget.repository,
                );
              }, childCount: filtered.length),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
