import 'package:flutter/material.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../data/repositories/whami_repository.dart';

class TruthModePanel extends StatelessWidget {
  final WhamiRepository repository;
  final VoidCallback onClose;

  const TruthModePanel({
    super.key,
    required this.repository,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tm = repository.truthMode;
    final episodes = tm.episodes;

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: WhamiAviation.glassPanel(radius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, color: WhamiAviation.cyan, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRUTH MODE',
                        style: WhamiAviation.overline(color: WhamiAviation.cyan),
                      ),
                      const Text(
                        'Claimed GPS vs trusted path',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: tm.enabled,
                  activeThumbColor: WhamiAviation.cyan,
                  onChanged: repository.setTruthModeEnabled,
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _legend(WhamiAviation.cyan, 'Trusted'),
                const SizedBox(width: 14),
                _legend(WhamiAviation.amber, 'GPS claim'),
                const Spacer(),
                Text(
                  '${tm.trustedTrail.length} / ${tm.claimedTrail.length} pts',
                  style: WhamiAviation.overline(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: episodes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No lie episodes yet. Spoof / GNSS jumps appear here with distance.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    shrinkWrap: true,
                    itemCount: episodes.length.clamp(0, 12),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final e = episodes[i];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: e.isOngoing
                                ? WhamiAviation.danger.withValues(alpha: 0.5)
                                : WhamiAviation.hairline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              e.isOngoing ? Icons.warning_amber : Icons.timeline,
                              color: e.isOngoing
                                  ? WhamiAviation.danger
                                  : WhamiAviation.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                e.isOngoing
                                    ? 'LIVE lie · ${e.distanceLabel}'
                                    : 'Episode · max ${e.distanceLabel}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '${e.sampleCount} samples',
                              style: WhamiAviation.overline(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label, style: WhamiAviation.overline(color: Colors.white70)),
      ],
    );
  }
}
