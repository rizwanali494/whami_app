import 'package:flutter/material.dart';
import '../theme/whami_aviation.dart';

/// Shared dark navy app-bar chrome for Offline / Sensors / Activity / Verify.
class WhamiScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  const WhamiScreenAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        (subtitle == null ? kToolbarHeight : 64) +
            (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: WhamiAviation.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: automaticallyImplyLeading,
      titleSpacing: WhamiLayout.pagePad(context),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: WhamiAviation.overline(color: WhamiAviation.cyan),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle ?? title,
            style: TextStyle(
              color: WhamiAviation.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: subtitle == null ? 17 : 15,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }
}

class WhamiSectionLabel extends StatelessWidget {
  final String text;
  final bool light;

  const WhamiSectionLabel(this.text, {super.key, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        WhamiLayout.pagePad(context),
        14,
        WhamiLayout.pagePad(context),
        6,
      ),
      child: Text(
        text.toUpperCase(),
        style: WhamiAviation.overline(
          color: light ? WhamiAviation.lightMuted : WhamiAviation.textMuted,
        ),
      ),
    );
  }
}

class WhamiGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool light;

  const WhamiGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration:
              light ? WhamiAviation.lightCard() : WhamiAviation.glassPanel(),
          child: body,
        ),
      ),
    );
  }
}

/// Compact aviation metric (ALT / GS / HDG / ACC).
class WhamiMetricCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool available;

  const WhamiMetricCell({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.available = true,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = available
        ? WhamiAviation.textPrimary
        : WhamiAviation.textMuted.withValues(alpha: 0.55);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: WhamiAviation.overline()),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WhamiAviation.metricValue(color: valueColor),
                ),
              ),
              const SizedBox(width: 4),
              Text(unit, style: WhamiAviation.metricUnit()),
            ],
          ),
        ],
      ),
    );
  }
}

class WhamiStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const WhamiStatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
