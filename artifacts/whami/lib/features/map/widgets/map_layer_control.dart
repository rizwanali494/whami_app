import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class MapLayerControl extends StatefulWidget {
  final Map<String, bool> layerVisibility;
  final Function(String key, bool visible) onLayerToggled;

  const MapLayerControl({
    super.key,
    required this.layerVisibility,
    required this.onLayerToggled,
  });

  @override
  State<MapLayerControl> createState() => _MapLayerControlState();
}

class _MapLayerControlState extends State<MapLayerControl> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final activeCount = widget.layerVisibility.values.where((v) => v).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded)
          Card(
            color: AppColors.headerBg,
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              width: 200,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                children: [
                  _buildToggleRow('mapTiles', 'Base Map Tiles', Icons.map_outlined, AppColors.gps),
                  _buildToggleRow('landmarks', 'Landmarks', Icons.location_on_outlined, AppColors.magnetic),
                  _buildToggleRow('seamap', 'Sea Charts', Icons.water_outlined, AppColors.gps),
                  _buildToggleRow('magnetic', 'Magnetic Grid', Icons.explore_outlined, AppColors.magnetic),
                  _buildToggleRow('opinions', 'Position Opinions', Icons.shield_outlined, AppColors.whami),
                  _buildToggleRow('uncertainty', 'Error Circles', Icons.radio_button_unchecked_outlined, AppColors.imu),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          heroTag: 'map_layers_fab',
          onPressed: () => setState(() => _expanded = !_expanded),
          backgroundColor: _expanded ? AppColors.whami : AppColors.headerBg,
          child: Badge(
            isLabelVisible: !_expanded && activeCount > 0,
            label: Text(
              '$activeCount',
              style: const TextStyle(color: AppColors.headerBg, fontWeight: FontWeight.bold, fontSize: 8),
            ),
            backgroundColor: AppColors.whami,
            child: Icon(
              Icons.layers,
              color: _expanded ? AppColors.headerBg : Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow(String key, String label, IconData icon, Color color) {
    final isVisible = widget.layerVisibility[key] ?? true;

    return Theme(
      data: ThemeData.dark(),
      child: CheckboxListTile(
        value: isVisible,
        onChanged: (val) => widget.onLayerToggled(key, val ?? false),
        activeColor: AppColors.whami,
        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        secondary: Icon(icon, color: isVisible ? color : Colors.white54, size: 18),
        title: Text(
          label,
          style: TextStyle(
            color: isVisible ? Colors.white : Colors.white54,
            fontSize: 11,
            fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
