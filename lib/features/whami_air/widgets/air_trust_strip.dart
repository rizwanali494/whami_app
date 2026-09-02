import 'package:flutter/material.dart';
import '../air_trust.dart';

/// Compact Green / Amber / Red / Grey advisory strip for map & EFB.
class AirTrustStrip extends StatelessWidget {
  final AirTrustSnapshot? snapshot;
  final bool compact;

  const AirTrustStrip({
    super.key,
    required this.snapshot,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final band = snapshot?.band ?? AirTrustBand.grey;
    final radius = snapshot?.confidenceRadiusM;
    final radiusLabel = radius == null
        ? '—'
        : radius >= 1000
            ? '±${(radius / 1000).toStringAsFixed(1)} km'
            : '±${radius.round()} m';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: band.color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            band == AirTrustBand.green
                ? Icons.check_circle
                : band == AirTrustBand.amber
                    ? Icons.warning_amber_rounded
                    : band == AirTrustBand.red
                        ? Icons.error
                        : Icons.help_outline,
            color: Colors.white,
            size: compact ? 22 : 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAMI-Air · ${band.label}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 13 : 15,
                    letterSpacing: 0.4,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    snapshot?.advisoryMessage ?? band.pilotLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            radiusLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
