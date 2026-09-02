import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Hard, unmistakable banner when GPS disagrees with real-world witnesses.
class SpoofAlarmBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onVerify;
  final VoidCallback? onDismiss;

  const SpoofAlarmBanner({
    super.key,
    required this.message,
    this.onVerify,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB71C1C),
      borderRadius: BorderRadius.circular(12),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.gpp_bad, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'GPS SUSPICIOUS — DON\'T TRUST THIS PIN',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      letterSpacing: 0.3,
                      height: 1.2,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.3,
              ),
            ),
            if (onVerify != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                  ),
                  onPressed: onVerify,
                  child: const Text(
                    'Lock to Real World',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'WHAMI cross-check: GPS jumped or disagrees with mag / baro / IMU / landmarks.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact chip when a visual landmark lock is active.
class RealWorldLockChip extends StatelessWidget {
  final String landmarkName;
  final VoidCallback? onUnlock;
  final VoidCallback? onTap;

  const RealWorldLockChip({
    super.key,
    required this.landmarkName,
    this.onUnlock,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.trustHigh,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Locked · $landmarkName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (onUnlock != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Unlock',
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open, color: Colors.white, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
