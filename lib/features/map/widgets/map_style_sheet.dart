import 'package:flutter/material.dart';
import '../../../core/config/map_basemap_style.dart';
import '../../../core/theme/whami_aviation.dart';

Future<void> showMapStyleSheet({
  required BuildContext context,
  required MapBasemapStyle current,
  required ValueChanged<MapBasemapStyle> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        decoration: const BoxDecoration(
          color: WhamiAviation.navy,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          20 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'MAP STYLE',
              style: WhamiAviation.overline(color: WhamiAviation.cyan),
            ),
            const SizedBox(height: 4),
            const Text(
              'Basemap appearance',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Real tile sources only. Cached tiles remain available offline.',
              style: WhamiAviation.body(),
            ),
            const SizedBox(height: 14),
            ...MapBasemapStyle.values.map((style) {
              final selected = style == current;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: selected
                      ? WhamiAviation.cyan.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      onSelected(style);
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(
                        children: [
                          Icon(
                            _icon(style),
                            color: selected
                                ? WhamiAviation.cyan
                                : Colors.white70,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  style.label,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  style.description,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  style.offlineNote,
                                  style: TextStyle(
                                    color: WhamiAviation.cyan
                                        .withValues(alpha: 0.75),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_circle,
                              color: WhamiAviation.cyan,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
  );
}

IconData _icon(MapBasemapStyle style) {
  switch (style) {
    case MapBasemapStyle.aviationDark:
      return Icons.dark_mode_outlined;
    case MapBasemapStyle.aviationLight:
      return Icons.light_mode_outlined;
    case MapBasemapStyle.satellite:
      return Icons.satellite_alt;
    case MapBasemapStyle.terrain:
      return Icons.terrain;
    case MapBasemapStyle.street:
      return Icons.map_outlined;
    case MapBasemapStyle.hybrid:
      return Icons.layers_outlined;
  }
}
