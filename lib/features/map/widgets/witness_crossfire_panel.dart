import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/witness_crossfire.dart';

/// Compact “jury” panel: who agrees, who is the outlier, tap for why.
class WitnessCrossfirePanel extends StatefulWidget {
  final WitnessCrossfire crossfire;
  final VoidCallback? onDismiss;

  const WitnessCrossfirePanel({
    super.key,
    required this.crossfire,
    this.onDismiss,
  });

  @override
  State<WitnessCrossfirePanel> createState() => _WitnessCrossfirePanelState();
}

class _WitnessCrossfirePanelState extends State<WitnessCrossfirePanel> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final c = widget.crossfire;
    if (!c.visible) return const SizedBox.shrink();

    return Material(
      color: const Color(0xFF0A1628),
      borderRadius: BorderRadius.circular(14),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.gavel, color: AppColors.whami, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'SENSOR CROSSFIRE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              c.headline,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.witnesses.map((w) {
                final selected = _expandedId == w.id;
                final color = w.isOutlier
                    ? AppColors.trustLow
                    : w.agrees
                        ? AppColors.trustHigh
                        : AppColors.trustMediumDark;
                return GestureDetector(
                  onTap: () => setState(
                    () => _expandedId = selected ? null : w.id,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: selected ? 0.35 : 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color, width: selected ? 2 : 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          w.shortCode,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          w.isOutlier
                              ? Icons.close
                              : w.agrees
                                  ? Icons.check
                                  : Icons.remove,
                          size: 14,
                          color: color,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_expandedId != null) ...[
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final w = c.witnesses.firstWhere(
                    (x) => x.id == _expandedId,
                    orElse: () => c.witnesses.first,
                  );
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          w.why,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${w.confidence}% · ${w.distanceFromTrustedM >= 1000 ? '${(w.distanceFromTrustedM / 1000).toStringAsFixed(1)} km' : '${w.distanceFromTrustedM.round()} m'} from trusted',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                'Tap a sensor chip to see why it broke.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                ),
              ),
            ],
            // Full-width close — never tucked under the right map FABs.
            if (widget.onDismiss != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0A1628),
                  ),
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
