import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class TileEngine {
  /// Generate MapLibre Style JSON using offline vector tiles or online raster.
  ///
  /// When [localMBTilesUrl] is provided (e.g. 'http://127.0.0.1:52341'), the
  /// style points to the local MBTiles tile server and renders a complete
  /// offline map with roads, buildings, water, parks, and POIs using the
  /// OpenMapTiles schema.
  ///
  /// When [localMBTilesUrl] is null/empty and [isOffline] is false, falls back
  /// to CartoDB raster tiles. When offline with no local pack, shows only the
  /// solid background colour.
  Map<String, dynamic> generateStyle({
    required bool isOffline,
    String? localMBTilesUrl,
  }) {
    final hasLocalTiles = localMBTilesUrl != null && localMBTilesUrl.isNotEmpty;

    // ── Sources ─────────────────────────────────────────────────────────────
    final Map<String, dynamic> sources = {};

    if (hasLocalTiles) {
      sources['openmaptiles'] = {
        'type': 'vector',
        'tiles': ['$localMBTilesUrl/{z}/{x}/{y}.pbf'],
        'minzoom': 0,
        'maxzoom': 14,
      };
    } else if (!isOffline) {
      sources['open-tiles'] = {
        'type': 'raster',
        'tiles': [
          'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
        ],
        'tileSize': 256,
        'attribution': '© OpenStreetMap, © CartoDB',
      };
    }

    // ── Layers ───────────────────────────────────────────────────────────────
    final List<Map<String, dynamic>> layers = [];

    // 1. Background — always present
    layers.add({
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#F2EFE9'},
    });

    if (hasLocalTiles) {
      // ── Full OpenMapTiles vector layers ──────────────────────────────────

      // 2. Water bodies
      layers.add({
        'id': 'water',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'water',
        'paint': {'fill-color': '#A8D1E7', 'fill-opacity': 0.9},
      });

      // 3. Waterways (rivers, canals, streams)
      layers.add({
        'id': 'waterway',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'waterway',
        'paint': {
          'line-color': '#7EC8E3',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            8,
            0.5,
            12,
            2.0,
            14,
            3.0,
          ],
        },
      });

      // 4. Land cover — grass & wood
      layers.add({
        'id': 'landcover-grass',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': [
          '==',
          ['get', 'class'],
          'grass',
        ],
        'paint': {'fill-color': '#D4EDBC', 'fill-opacity': 0.8},
      });
      layers.add({
        'id': 'landcover-wood',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': [
          '==',
          ['get', 'class'],
          'wood',
        ],
        'paint': {'fill-color': '#BDDFAD', 'fill-opacity': 0.75},
      });

      // 5. Landuse zones
      layers.add({
        'id': 'landuse-park',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['park', 'pitch', 'recreation_ground', 'garden'],
          ],
        ],
        'paint': {'fill-color': '#C8E6C0', 'fill-opacity': 0.85},
      });
      layers.add({
        'id': 'landuse-residential',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          '==',
          ['get', 'class'],
          'residential',
        ],
        'paint': {'fill-color': '#EBEBEB', 'fill-opacity': 0.6},
      });
      layers.add({
        'id': 'landuse-commercial',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['commercial', 'retail', 'industrial'],
          ],
        ],
        'paint': {'fill-color': '#F5DEB3', 'fill-opacity': 0.5},
      });

      // 6. Park fill
      layers.add({
        'id': 'park-fill',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'park',
        'paint': {'fill-color': '#C8E6C0', 'fill-opacity': 0.7},
      });

      // 7. Buildings
      layers.add({
        'id': 'building',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'building',
        'minzoom': 13,
        'paint': {
          'fill-color': '#D9C9B5',
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            13,
            0.4,
            15,
            0.9,
          ],
          'fill-outline-color': '#C4A882',
        },
      });

      // 8. Road casings (drawn first so fills appear on top)
      layers.add({
        'id': 'road-motorway-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'motorway',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#D4820A',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            5,
            2.0,
            10,
            6.0,
            14,
            10.0,
          ],
        },
      });
      layers.add({
        'id': 'road-trunk-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'trunk',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#C9A000',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            6,
            1.5,
            10,
            5.5,
            14,
            9.0,
          ],
        },
      });
      layers.add({
        'id': 'road-primary-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'primary',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#BBBBBB',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            7,
            1.5,
            10,
            5.0,
            14,
            8.5,
          ],
        },
      });
      layers.add({
        'id': 'road-secondary-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['secondary', 'tertiary'],
          ],
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#C4C4C4',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            9,
            1.0,
            12,
            4.0,
            14,
            7.0,
          ],
        },
      });

      // 9. Road fills
      layers.add({
        'id': 'road-motorway',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'motorway',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#FFA726',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            5,
            1.0,
            10,
            4.0,
            14,
            7.0,
          ],
        },
      });
      layers.add({
        'id': 'road-trunk',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'trunk',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#FFD54F',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            6,
            1.0,
            10,
            3.5,
            14,
            6.5,
          ],
        },
      });
      layers.add({
        'id': 'road-primary',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'primary',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#FFFFFF',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            7,
            0.8,
            10,
            3.0,
            14,
            6.0,
          ],
        },
      });
      layers.add({
        'id': 'road-secondary',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'secondary',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#FFFFFF',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            9,
            0.6,
            12,
            2.5,
            14,
            5.0,
          ],
        },
      });
      layers.add({
        'id': 'road-tertiary',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          '==',
          ['get', 'class'],
          'tertiary',
        ],
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#F5F5F5',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            0.4,
            12,
            2.0,
            14,
            4.0,
          ],
        },
      });
      layers.add({
        'id': 'road-minor',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['minor', 'service', 'track'],
          ],
        ],
        'minzoom': 12,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#EEEEEE',
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            12,
            0.3,
            14,
            2.0,
          ],
        },
      });
      layers.add({
        'id': 'road-path',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['path', 'pedestrian', 'cycleway'],
          ],
        ],
        'minzoom': 13,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#C8B89A',
          'line-width': 1.0,
          'line-dasharray': [2, 2],
        },
      });

      // 10. Admin boundaries
      layers.add({
        'id': 'boundary-country',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'boundary',
        'filter': [
          '==',
          ['get', 'admin_level'],
          2,
        ],
        'paint': {
          'line-color': '#9E9E9E',
          'line-width': 1.5,
          'line-dasharray': [4, 3],
        },
      });
      layers.add({
        'id': 'boundary-state',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'boundary',
        'filter': [
          '==',
          ['get', 'admin_level'],
          4,
        ],
        'minzoom': 6,
        'paint': {
          'line-color': '#BDBDBD',
          'line-width': 1.0,
          'line-dasharray': [3, 3],
        },
      });

      // 11. Road name labels
      layers.add({
        'id': 'road-name',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'transportation_name',
        'minzoom': 12,
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 10,
          'symbol-placement': 'line',
          'text-max-angle': 30,
        },
        'paint': {
          'text-color': '#555555',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 12. Water name labels
      layers.add({
        'id': 'water-name',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'water_name',
        'minzoom': 10,
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 11,
          'symbol-placement': 'point',
        },
        'paint': {
          'text-color': '#3A7FC1',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 13. Waterway name labels
      layers.add({
        'id': 'waterway-name',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'waterway',
        'minzoom': 13,
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 10,
          'symbol-placement': 'line',
        },
        'paint': {
          'text-color': '#3A7FC1',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 14. Park name labels
      layers.add({
        'id': 'park-name',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'park',
        'minzoom': 12,
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 11,
          'symbol-placement': 'point',
        },
        'paint': {
          'text-color': '#2E7D32',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 15. POI labels
      layers.add({
        'id': 'poi-label',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'poi',
        'minzoom': 14,
        'filter': [
          '<=',
          ['get', 'rank'],
          3,
        ],
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 11,
          'text-max-width': 8,
          'text-anchor': 'top',
          'text-offset': [0, 0.5],
        },
        'paint': {
          'text-color': '#333333',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 16. Place labels — suburbs & neighbourhoods
      layers.add({
        'id': 'place-suburb',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 11,
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['suburb', 'neighbourhood', 'quarter'],
          ],
        ],
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': 12,
          'text-transform': 'uppercase',
          'text-letter-spacing': 0.1,
        },
        'paint': {
          'text-color': '#757575',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 17. Place labels — towns & villages
      layers.add({
        'id': 'place-town',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 8,
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['village', 'town'],
          ],
        ],
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            8,
            11,
            12,
            14,
          ],
        },
        'paint': {
          'text-color': '#333333',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.0,
        },
      });

      // 18. Place labels — cities
      layers.add({
        'id': 'place-city',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 4,
        'filter': [
          'in',
          ['get', 'class'],
          [
            'literal',
            ['city', 'capital'],
          ],
        ],
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:en'],
            ['get', 'name'],
          ],
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            4,
            10,
            8,
            16,
            12,
            20,
          ],
        },
        'paint': {
          'text-color': '#1A1A1A',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      });
    } else if (!isOffline) {
      // Online CartoDB raster fallback (no local pack loaded)
      layers.add({
        'id': 'base-tiles',
        'type': 'raster',
        'source': 'open-tiles',
        'minzoom': 0,
        'maxzoom': 14,
      });
    }
    // else: offline + no pack → only background layer (already added above)

    return {
      'version': 8,
      'name': 'WHAMI Offline Vector',
      // Use MapLibre demo glyphs for text labels (online). In a future update,
      // bundle Noto Sans PBFs in assets/ for fully-offline label rendering.
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
  Future<void> updateVisibility(Map<String, bool> visibility) async {
    final c = _controller;
    if (c == null) return;

    final landmarksVisible = visibility['landmarks'] == true;
    final magneticVisible = visibility['magnetic'] == true;
    final seamapVisible = visibility['seamap'] == true;

    try {
      await c.setLayerProperties(
        'landmark-layer',
        SymbolLayerProperties(
          visibility: landmarksVisible ? 'visible' : 'none',
        ),
      );
    } catch (_) {}

    try {
      await c.setLayerProperties(
        'magnetic-layer',
        CircleLayerProperties(visibility: magneticVisible ? 'visible' : 'none'),
      );
    } catch (_) {}

    try {
      await c.setLayerProperties(
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

    try {
      await c.clearCircles();
      await c.clearSymbols();
    } catch (e) {
      debugPrint('[OverlayEngine] clearCircles/clearSymbols failed: $e');
      return;
    }

    if (!visible) return;

    for (final op in opinions) {
      if (op.confidence == 0 || !op.isActive) continue;

      final color = _colorForSource(op.sourceType);
      final hexColor =
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

      try {
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
      } catch (e) {
        debugPrint('[OverlayEngine] addCircle/addSymbol failed: $e');
        return; // Stop drawing — annotation manager likely invalidated
      }
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
