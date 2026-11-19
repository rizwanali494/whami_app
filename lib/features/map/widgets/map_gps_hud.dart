import 'package:flutter/material.dart';
import '../../../core/theme/whami_aviation.dart';
import '../../../core/widgets/whami_chrome.dart';
import '../../../data/services/gps_service.dart';

/// Compact aviation GNSS HUD with integrated tracking state.
class MapGpsHud extends StatelessWidget {
  final GpsReading? reading;
  final bool gpsEnabled;
  final bool isTracking;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onStopTracking;
  final VoidCallback? onStartTracking;

  const MapGpsHud({
    super.key,
    required this.reading,
    this.gpsEnabled = true,
    this.isTracking = true,
    this.expanded = false,
    this.onToggleExpand,
    this.onStopTracking,
    this.onStartTracking,
  });

  static String _fmtAlt(GpsReading? r) {
    if (r == null) return '—';
    final m = r.altitude;
    if (!m.isFinite) return '—';
    return m.round().toString();
  }

  static String _fmtGs(GpsReading? r) {
    if (r == null) return '—';
    final ms = r.speed;
    if (!ms.isFinite || ms < 0) return '—';
    final kt = ms * 1.943844;
    if (kt < 0.5) return '0';
    return kt < 10 ? kt.toStringAsFixed(1) : kt.round().toString();
  }

  static String _fmtHdg(GpsReading? r) {
    if (r == null) return '—';
    final h = r.heading;
    final ms = r.speed;
    if (!h.isFinite || h < 0 || !ms.isFinite || ms < 0.5) return '—';
    return '${h.round() % 360}';
  }

  static String _fmtAcc(GpsReading? r) {
    if (r == null) return '—';
    final a = r.accuracy;
    if (!a.isFinite || a <= 0) return '—';
    return a < 10 ? a.toStringAsFixed(1) : a.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final live = gpsEnabled && reading != null;
    final tablet = WhamiLayout.isTablet(context);

    String statusLabel;
    Color statusColor;
    if (!isTracking) {
      statusLabel = 'STANDBY';
      statusColor = WhamiAviation.textMuted;
    } else if (!gpsEnabled) {
      statusLabel = 'SENSORS ONLY';
      statusColor = WhamiAviation.amber;
    } else if (!live) {
      statusLabel = 'NO FIX';
      statusColor = WhamiAviation.danger;
    } else {
      statusLabel = 'LIVE';
      statusColor = WhamiAviation.success;
    }

    return Semantics(
      label: 'GNSS HUD $statusLabel',
      child: Container(
        constraints: BoxConstraints(maxWidth: tablet ? 480 : 400),
        decoration: WhamiAviation.glassPanel(
          radius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                tablet ? 14 : 12,
                10,
                8,
                expanded ? 6 : 10,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.55),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: WhamiAviation.overline(color: statusColor),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        live ? 'GNSS' : (!gpsEnabled ? '' : 'WAITING'),
                        style: WhamiAviation.overline(
                          color: WhamiAviation.textMuted,
                        ),
                      ),
                      const Spacer(),
                      if (isTracking && onStopTracking != null)
                        TextButton(
                          onPressed: onStopTracking,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'STOP',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0.6,
                            ),
                          ),
                        )
                      else if (!isTracking && onStartTracking != null)
                        TextButton(
                          onPressed: onStartTracking,
                          style: TextButton.styleFrom(
                            foregroundColor: WhamiAviation.cyan,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'START',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      if (onToggleExpand != null)
                        IconButton(
                          tooltip: expanded ? 'Collapse' : 'Expand',
                          onPressed: onToggleExpand,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          icon: Icon(
                            expanded
                                ? Icons.expand_more
                                : Icons.expand_less,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      WhamiMetricCell(
                        label: 'ALT',
                        value: _fmtAlt(reading),
                        unit: 'm',
                        available: live,
                      ),
                      _Divider(),
                      WhamiMetricCell(
                        label: 'GS',
                        value: _fmtGs(reading),
                        unit: 'kt',
                        available: live,
                      ),
                      _Divider(),
                      WhamiMetricCell(
                        label: 'HDG',
                        value: _fmtHdg(reading),
                        unit: '°',
                        available: live,
                      ),
                      _Divider(),
                      WhamiMetricCell(
                        label: 'ACC',
                        value: _fmtAcc(reading),
                        unit: 'm',
                        available: live,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (expanded && reading != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(
                  '${reading!.latitude.toStringAsFixed(5)}, '
                  '${reading!.longitude.toStringAsFixed(5)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: WhamiAviation.hairlineStrong,
    );
  }
}
