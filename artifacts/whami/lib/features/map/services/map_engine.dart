import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class TileEngine {
  /// Generate MapLibre Style JSON using offline or online base maps.
  /// When offline, it points to local sources or falls back to solid background.
  Map<String, dynamic> generateStyle({
    required bool isOffline,
    String? localMBTilesUrl,
  }) {
    final Map<String, dynamic> sources = {
      'open-tiles': {
        'type': 'raster',
        'tiles': [
          'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
        ],
        'tileSize': 256,
        'attribution': '© OpenStreetMap, © CartoDB',
      },
    };

    final List<dynamic> layers = [
      {
        'id': 'solid-background',
        'type': 'background',
        'paint': {'background-color': '#E8EDF2'},
      },
      {
        'id': 'base-tiles',
        'type': 'raster',
        'source': 'open-tiles',
        'minzoom': 0,
        'maxzoom': 14,
        'layout': {
          'visibility':
              (isOffline ||
                  (localMBTilesUrl != null && localMBTilesUrl.isNotEmpty))
              ? 'none'
              : 'visible',
        },
      },
    ];

    if (localMBTilesUrl != null && localMBTilesUrl.isNotEmpty) {
      sources['mbtiles-source'] = {
        'type': 'vector',
        'tiles': ['$localMBTilesUrl/{z}/{x}/{y}.pbf'],
        'minzoom': 0,
        'maxzoom': 14,
      };

      layers.addAll([
        {
          'id': 'landcover',
          'type': 'fill',
          'source': 'mbtiles-source',
          'source-layer': 'landcover',
          'paint': {'fill-color': '#D8E8C8', 'fill-opacity': 0.8},
        },
        {
          'id': 'landuse',
          'type': 'fill',
          'source': 'mbtiles-source',
          'source-layer': 'landuse',
          'paint': {'fill-color': '#E5E0D8', 'fill-opacity': 0.8},
        },
        {
          'id': 'water',
          'type': 'fill',
          'source': 'mbtiles-source',
          'source-layer': 'water',
          'paint': {'fill-color': '#A0C8F0', 'fill-opacity': 1.0},
        },
        {
          'id': 'transportation',
          'type': 'line',
          'source': 'mbtiles-source',
          'source-layer': 'transportation',
          'paint': {
            'line-color': '#FFFFFF',
            'line-width': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10,
              1.0,
              14,
              3.0,
              18,
              10.0,
            ],
          },
        },
        {
          'id': 'building',
          'type': 'fill',
          'source': 'mbtiles-source',
          'source-layer': 'building',
          'paint': {
            'fill-color': '#CBD1D6',
            'fill-opacity': 0.7,
            'fill-outline-color': '#A9B0B7',
          },
        },
        {
          'id': 'place',
          'type': 'symbol',
          'source': 'mbtiles-source',
          'source-layer': 'place',
          'layout': {
            'text-field': ['get', 'name:latin'],
            'text-size': [
              'interpolate',
              ['linear'],
              ['zoom'],
              10,
              12,
              14,
              16,
            ],
            'text-font': [
              'Open Sans Regular',
            ], // Fallback if needed, wait maplibre usually has local fonts or needs glyphs
          },
          'paint': {
            'text-color': '#333333',
            'text-halo-color': '#FFFFFF',
            'text-halo-width': 1,
          },
        },
      ]);
    }

    return {
      'version': 8,
      'name': 'WHAMI Dynamic Style',
      // If we use text-font, we MUST provide glyphs. Let's remove text-font so it uses default/system, or provide a dummy glyphs URL.
      'glyphs': 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
      'sources': sources,
      'layers': layers,
    };
  }
}

class LayerEngine {
  MapLibreMapController? _controller;

  void attach(MapLibreMapController controller) {
    _controller = controller;
  }

  void detach() {
    _controller = null;
  }

  /// Removes all dynamically added layers and sources when a pack is deactivated
  Future<void> clearLayers() async {
    final c = _controller;
    if (c == null) return;

    try {
      await c.removeLayer('landmark-layer');
      await c.removeSource('landmarks');
      await c.removeLayer('magnetic-layer');
      await c.removeSource('magnetic');
      await c.removeLayer('seamap-layer');
      await c.removeSource('seamap');
    } catch (_) {}
  }

  /// Setup the data sources and rendering layers for landmarks, seamap, and magnetic baselines.
  Future<void> setupLayers({
    required String packId,
    required Map<String, dynamic> landmarksGeo,
    required Map<String, dynamic> magneticGeo,
    required Map<String, dynamic> seamapGeo,
  }) async {
    final c = _controller;
    if (c == null) return;

    // Clear existing
    try {
      await c.removeLayer('landmark-layer');
      await c.removeSource('landmarks');
      await c.removeLayer('magnetic-layer');
      await c.removeSource('magnetic');
      await c.removeLayer('seamap-layer');
      await c.removeSource('seamap');
    } catch (_) {}

    // Add Landmarks symbol layer
    await c.addGeoJsonSource('landmarks', landmarksGeo);
    await c.addSymbolLayer(
      'landmarks',
      'landmark-layer',
      const SymbolLayerProperties(
        iconImage: 'landmark-icon',
        iconSize: 1.0,
        textField: '{name}',
        textColor: '#FFFFFF',
        textSize: 10,
        textOffset: [0, 1.5],
      ),
    );

    // Add Magnetic circle layer
    await c.addGeoJsonSource('magnetic', magneticGeo);
    await c.addCircleLayer(
      'magnetic',
      'magnetic-layer',
      const CircleLayerProperties(
        circleRadius: 5.0,
        circleColor: '#E24B4A',
        circleOpacity: 0.6,
      ),
    );

    // Add Seamap line layer
    await c.addGeoJsonSource('seamap', seamapGeo);
    await c.addLineLayer(
      'seamap',
      'seamap-layer',
      const LineLayerProperties(lineColor: '#00E5FF', lineWidth: 3.0),
    );
  }

  /// Toggle layers visibility
  void updateVisibility(Map<String, bool> visibility) {
    final c = _controller;
    if (c == null) return;

    final landmarksVisible = visibility['landmarks'] == true;
    final magneticVisible = visibility['magnetic'] == true;
    final seamapVisible = visibility['seamap'] == true;

    try {
      c.setLayerProperties(
        'landmark-layer',
        SymbolLayerProperties(
          visibility: landmarksVisible ? 'visible' : 'none',
        ),
      );
      c.setLayerProperties(
        'magnetic-layer',
        CircleLayerProperties(visibility: magneticVisible ? 'visible' : 'none'),
      );
      c.setLayerProperties(
        'seamap-layer',
        LineLayerProperties(visibility: seamapVisible ? 'visible' : 'none'),
      );
    } catch (_) {}
  }
}

class CameraEngine {
  MapLibreMapController? _controller;

  void attach(MapLibreMapController controller) {
    _controller = controller;
  }

  void detach() {
    _controller = null;
  }

  /// Move camera to target lat/lng with specified zoom level
  void centerOn(double lat, double lng, {double zoom = 14.5}) {
    final c = _controller;
    if (c == null) return;
    c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), zoom));
  }

  /// Move camera keeping current zoom
  void panTo(double lat, double lng) {
    final c = _controller;
    if (c == null) return;
    c.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
  }
}

class OverlayEngine {
  MapLibreMapController? _controller;

  void attach(MapLibreMapController controller) {
    _controller = controller;
  }

  void detach() {
    _controller = null;
  }

  /// Draw consensus position opinions onto the map
  Future<void> drawOpinions(
    List<PositionOpinion> opinions,
    bool visible,
  ) async {
    final c = _controller;
    if (c == null) return;

    await c.clearCircles();
    await c.clearSymbols();

    if (!visible) return;

    for (final op in opinions) {
      if (op.confidence == 0 || !op.isActive) continue;

      final color = _colorForSource(op.sourceType);
      final hexColor =
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

      await c.addCircle(
        CircleOptions(
          geometry: LatLng(op.latitude, op.longitude),
          circleRadius: op.sourceType == 'whami' ? 12.0 : 8.0,
          circleColor: hexColor,
          circleOpacity: 0.85,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 1.5,
        ),
      );

      await c.addSymbol(
        SymbolOptions(
          geometry: LatLng(op.latitude, op.longitude),
          textField: op.shortCode,
          textColor: '#FFFFFF',
          textSize: 9.0,
          textAnchor: 'center',
        ),
      );
    }
  }

  Color _colorForSource(String sourceType) {
    switch (sourceType) {
      case 'whami':
        return AppColors.whami;
      case 'gps':
        return AppColors.gps;
      case 'landmark':
        return AppColors.landmark;
      case 'magnetic':
        return AppColors.magnetic;
      case 'sextant':
        return AppColors.sextant;
      case 'imu':
        return AppColors.imu;
      default:
        return Colors.white;
    }
  }
}

class MapEngine {
  final TileEngine tile = TileEngine();
  final LayerEngine layer = LayerEngine();
  final CameraEngine camera = CameraEngine();
  final OverlayEngine overlay = OverlayEngine();

  MapLibreMapController? _controller;

  bool get isAttached => _controller != null;

  void attach(MapLibreMapController controller) {
    _controller = controller;
    layer.attach(controller);
    camera.attach(controller);
    overlay.attach(controller);
  }

  void detach() {
    layer.detach();
    camera.detach();
    overlay.detach();
    _controller = null;
  }
}
