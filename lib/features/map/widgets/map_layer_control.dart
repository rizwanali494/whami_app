import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/whami_aviation.dart';

class MapLayerControl extends StatefulWidget {
  final Map<String, bool> layerVisibility;
  final Function(String key, bool visible) onLayerToggled;
  final VoidCallback? onOpenMapStyle;
  final String? mapStyleLabel;

  const MapLayerControl({
    super.key,
    required this.layerVisibility,
    required this.onLayerToggled,
    this.onOpenMapStyle,
    this.mapStyleLabel,
  });

  @override
  State<MapLayerControl> createState() => _MapLayerControlState();
}

class _MapLayerControlState extends State<MapLayerControl> {
  bool _expanded = false;

  void _collapse() => setState(() => _expanded = false);
  void _expand() => setState(() => _expanded = true);

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.layerVisibility.values.where((v) => v).length;
    final maxPanelHeight = MediaQuery.sizeOf(context).height * 0.42;
    final size = WhamiLayout.mapFabSize(context);

    if (!_expanded) {
      return _LayersSquareButton(
        size: size,
        activeCount: activeCount,
        highlighted: false,
        onTap: _expand,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Material(
          color: Colors.transparent,
          child: Container(
            decoration: WhamiAviation.glassPanel(
              radius: BorderRadius.circular(14),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 240,
                maxHeight: maxPanelHeight,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onOpenMapStyle != null)
                      ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        leading: const Icon(
                          Icons.map_outlined,
                          color: WhamiAviation.cyan,
                          size: 20,
                        ),
                        title: Text(
                          'Map style',
                          style: WhamiAviation.body(
                            color: WhamiAviation.textPrimary,
                          ).copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          widget.mapStyleLabel ?? 'Choose basemap',
                          style: WhamiAviation.overline(
                            color: WhamiAviation.textMuted,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: WhamiAviation.textMuted,
                          size: 20,
                        ),
                        onTap: () {
                          _collapse();
                          widget.onOpenMapStyle!();
                        },
                      ),
                    if (widget.onOpenMapStyle != null)
                      const Divider(
                        height: 8,
                        color: WhamiAviation.hairline,
                      ),
                    _buildToggleRow(
                      'mapTiles',
                      'Base Map Tiles',
                      Icons.map_outlined,
                      AppColors.gps,
                    ),
                    _buildToggleRow(
                      'rangeRings',
                      'Range Rings',
                      Icons.radar_outlined,
                      AppColors.gps,
                    ),
                    _buildToggleRow(
                      'landmarks',
                      'Landmarks',
                      Icons.location_on_outlined,
                      AppColors.magnetic,
                    ),
                    _buildToggleRow(
                      'seamap',
                      'Sea Charts',
                      Icons.water_outlined,
                      AppColors.gps,
                    ),
                    _buildToggleRow(
                      'magnetic',
                      'Magnetic Grid',
                      Icons.explore_outlined,
                      AppColors.magnetic,
                    ),
                    _buildToggleRow(
                      'opinions',
                      'Position Opinions',
                      Icons.shield_outlined,
                      AppColors.whami,
                    ),
                    _buildToggleRow(
                      'uncertainty',
                      'Error Circles',
                      Icons.radio_button_unchecked_outlined,
                      AppColors.imu,
                    ),
                    _buildToggleRow(
                      'spoofHeat',
                      'Spoof Heatmap',
                      Icons.whatshot_outlined,
                      AppColors.trustLow,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _collapse,
                child: Ink(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: WhamiAviation.charcoal.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 22,
                    color: WhamiAviation.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _LayersSquareButton(
              size: size,
              activeCount: activeCount,
              highlighted: true,
              onTap: _collapse,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggleRow(String key, String label, IconData icon, Color color) {
    final isVisible = widget.layerVisibility[key] ?? true;
    final textColor =
        isVisible ? WhamiAviation.textPrimary : WhamiAviation.textMuted;

    return Theme(
      data: ThemeData.dark(),
      child: CheckboxListTile(
        value: isVisible,
        onChanged: (val) => widget.onLayerToggled(key, val ?? false),
        activeColor: WhamiAviation.cyan,
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        secondary: Icon(
          icon,
          color: isVisible ? color : WhamiAviation.textMuted,
          size: 18,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LayersSquareButton extends StatelessWidget {
  final double size;
  final int activeCount;
  final bool highlighted;
  final VoidCallback onTap;

  const _LayersSquareButton({
    required this.size,
    required this.activeCount,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: WhamiAviation.charcoal.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlighted
                  ? WhamiAviation.cyan.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Badge(
            isLabelVisible: !highlighted && activeCount > 0,
            label: Text(
              '$activeCount',
              style: const TextStyle(
                color: WhamiAviation.navy,
                fontWeight: FontWeight.bold,
                fontSize: 8,
              ),
            ),
            backgroundColor: WhamiAviation.cyan,
            child: Icon(
              Icons.layers,
              color: highlighted ? WhamiAviation.cyan : WhamiAviation.cyan,
              size: WhamiLayout.mapFabIcon(context),
            ),
          ),
        ),
      ),
    );
  }
}
