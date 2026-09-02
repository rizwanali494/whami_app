import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/whami_repository.dart';
import 'widgets/air_trust_strip.dart';

/// Phase 3 — WHAMI Pro Ground Station style dashboard (phone preview + Windows).
///
/// On Toughbook / Windows this is the primary large-screen command view.
/// Phone remains the live sensor host; this screen reviews fusion + logs.
class GroundStationScreen extends StatefulWidget {
  final WhamiRepository repository;

  const GroundStationScreen({super.key, required this.repository});

  @override
  State<GroundStationScreen> createState() => _GroundStationScreenState();
}

class _GroundStationScreenState extends State<GroundStationScreen> {
  List<String> _flights = [];

  WhamiRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    repo.addListener(_refresh);
    _loadFlights();
  }

  @override
  void dispose() {
    repo.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFlights() async {
    final dirs = await repo.airRecorder.listFlights();
    if (!mounted) return;
    setState(() {
      _flights = dirs
          .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final platformLabel = defaultTargetPlatform == TargetPlatform.windows
        ? 'Windows Ground Station'
        : defaultTargetPlatform == TargetPlatform.linux
            ? 'Linux Ground Station'
            : 'Ground Station (phone preview)';

    return Scaffold(
      appBar: AppBar(
        title: Text('WHAMI Pro · $platformLabel'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh flights',
            onPressed: _loadFlights,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _dashboard()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _flightList()),
                ],
              )
            : ListView(
                children: [
                  _dashboard(),
                  const SizedBox(height: 16),
                  SizedBox(height: 280, child: _flightList()),
                ],
              ),
      ),
    );
  }

  Widget _dashboard() {
    final air = repo.airTrust;
    final opinions = repo.getPositionOpinions();
    final fusion = repo.lastFusion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AirTrustStrip(snapshot: air),
        const SizedBox(height: 12),
        Text(
          'ADVISORY — phone sensors → Ground Station review',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('Trust', '${repo.trustScore}%'),
            _chip(
              'Radius',
              air == null ? '—' : '±${air.confidenceRadiusM.round()} m',
            ),
            _chip(
              'WMM Δ',
              air?.wmmResidualUt == null
                  ? '—'
                  : '${air!.wmmResidualUt!.toStringAsFixed(1)} µT',
            ),
            _chip(
              'Baro Δ',
              air?.baroGpsAltDeltaM == null
                  ? '—'
                  : '${air!.baroGpsAltDeltaM!.round()} m',
            ),
            _chip('Kp', airPreferencesKp()),
            _chip(
              'Recording',
              repo.airRecorder.isRecording ? 'ON' : 'off',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Position opinions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...opinions.map(
          (o) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 14,
              child: Text(o.shortCode, style: const TextStyle(fontSize: 11)),
            ),
            title: Text(o.name),
            subtitle: Text(o.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              o.status == 'unavailable' ? '—' : '${o.confidence}%',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (fusion != null) ...[
          const SizedBox(height: 8),
          Text(
            'Hierarchy: ${fusion.sourceHierarchy.join(" › ")}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  String airPreferencesKp() {
    // Avoid importing prefs here for chip; show from repo kp service.
    return repo.kpService.kp.toStringAsFixed(0);
  }

  Widget _flightList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mission logs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _flights.isEmpty
                  ? const Center(
                      child: Text(
                        'No flights recorded yet.\nEnable Air mode and start tracking.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _flights.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final id = _flights[i];
                        return ListTile(
                          dense: true,
                          title: Text(id, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.archive_outlined),
                            tooltip: 'Export ZIP',
                            onPressed: () async {
                              final zip =
                                  await repo.airRecorder.exportFlightZip(id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Exported ${zip.path}')),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}
