import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../data/services/trust_copilot.dart';

class TrustCopilotStrip extends StatelessWidget {
  final TrustAdvisory advisory;

  const TrustCopilotStrip({super.key, required this.advisory});

  @override
  Widget build(BuildContext context) {
    final color = switch (advisory.severity) {
      'critical' => WhamiAviation.danger,
      'caution' => WhamiAviation.amber,
      _ => WhamiAviation.cyan,
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: WhamiAviation.navy.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${advisory.code} · ${advisory.title}'.toUpperCase(),
                    style: WhamiAviation.overline(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    advisory.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (advisory.actionLabel != null && advisory.actionRoute != null)
              TextButton(
                onPressed: () => context.go(advisory.actionRoute!),
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  advisory.actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
