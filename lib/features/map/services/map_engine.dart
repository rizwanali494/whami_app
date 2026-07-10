import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class TileEngine {
  /// Generate the base MapLibre style JSON. This now contains only the
  /// background layer — every real source/layer (vector base map, raster
  /// fallback, overlay layers) is added imperatively via the controller API
  /// in LayerEngine after the style loads. See LayerEngine.setupBaseMapLayers
  /// for why: embedding sources/layers directly in this JSON string does not
  /// reliably render for a custom local vector source in this maplibre_gl
  /// version, confirmed via direct device testing.
  Map<String, dynamic> generateStyle({String? glyphsUrl}) {
    return {
      'version': 8,
      'name': 'WHAMI Offline Vector',
      'sources': <String, dynamic>{},
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#F2EFE9'},
        },
      ],
      // Bundled Noto Sans glyphs served locally (see GlyphServer) — works
      // identically online and offline, no external dependency.
      if (glyphsUrl != null && glyphsUrl.isNotEmpty)
        'glyphs': '$glyphsUrl/{fontstack}/{range}.pbf',
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

  static const _nameExpr = ['coalesce', ['get', 'name:en'], ['get', 'name']];

  /// Sets up the base map (roads, water, buildings, land use, labels — or
  /// the online raster fallback) via the imperative controller API.
  ///
  /// Embedding these directly in the style JSON string passed to
  /// setStyle() does not reliably render for a custom local vector source
  /// in this maplibre_gl version — confirmed via direct device testing,
  /// where the exact same data rendered correctly when added imperatively
  /// but never rendered when baked into the style JSON. The overlay layers
  /// below (landmarks/magnetic/seamap) already used this imperative
  /// pattern, which is why they always worked while the base map didn't.
  Future<void> setupBaseMapLayers({
    required bool isOffline,
    String? localMBTilesUrl,
    String? worldBasemapUrl,
  }) async {
    final c = _controller;
    if (c == null) return;

    final hasLocalTiles =
        localMBTilesUrl != null && localMBTilesUrl.isNotEmpty;

    if (hasLocalTiles) {
      await c.addSource(
        'openmaptiles',
        VectorSourceProperties(
          tiles: ['$localMBTilesUrl/{z}/{x}/{y}.pbf'],
          minzoom: 0,
          maxzoom: 14,
        ),
      );

      await c.addFillLayer(
        'openmaptiles',
        'water',
        const FillLayerProperties(fillColor: '#A8D1E7', fillOpacity: 0.9),
        sourceLayer: 'water',
      );
      await c.addLineLayer(
        'openmaptiles',
        'waterway',
        const LineLayerProperties(
          lineColor: '#7EC8E3',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 8, 0.5, 12, 2.0, 14, 3.0,
          ],
        ),
        sourceLayer: 'waterway',
      );
      await c.addFillLayer(
        'openmaptiles',
        'landcover-grass',
        const FillLayerProperties(fillColor: '#D4EDBC', fillOpacity: 0.8),
        sourceLayer: 'landcover',
        filter: ['==', ['get', 'class'], 'grass'],
      );
      await c.addFillLayer(
        'openmaptiles',
        'landcover-wood',
        const FillLayerProperties(fillColor: '#BDDFAD', fillOpacity: 0.75),
        sourceLayer: 'landcover',
        filter: ['==', ['get', 'class'], 'wood'],
      );
      await c.addFillLayer(
        'openmaptiles',
        'landuse-park',
        const FillLayerProperties(fillColor: '#C8E6C0', fillOpacity: 0.85),
        sourceLayer: 'landuse',
        filter: [
          'in', ['get', 'class'],
          ['literal', ['park', 'pitch', 'recreation_ground', 'garden']],
        ],
      );
      await c.addFillLayer(
        'openmaptiles',
        'landuse-residential',
        const FillLayerProperties(fillColor: '#EBEBEB', fillOpacity: 0.6),
        sourceLayer: 'landuse',
        filter: ['==', ['get', 'class'], 'residential'],
      );
      await c.addFillLayer(
        'openmaptiles',
        'landuse-commercial',
        const FillLayerProperties(fillColor: '#F5DEB3', fillOpacity: 0.5),
        sourceLayer: 'landuse',
        filter: [
          'in', ['get', 'class'],
          ['literal', ['commercial', 'retail', 'industrial']],
        ],
      );
      await c.addFillLayer(
        'openmaptiles',
        'park-fill',
        const FillLayerProperties(fillColor: '#C8E6C0', fillOpacity: 0.7),
        sourceLayer: 'park',
      );
      await c.addFillLayer(
        'openmaptiles',
        'building',
        const FillLayerProperties(
          fillColor: '#D9C9B5',
          fillOpacity: [
            'interpolate', ['linear'], ['zoom'], 13, 0.4, 15, 0.9,
          ],
          fillOutlineColor: '#C4A882',
        ),
        sourceLayer: 'building',
        minzoom: 13,
      );

      // Road casings (drawn first so fills appear on top)
      await c.addLineLayer(
        'openmaptiles',
        'road-motorway-casing',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#D4820A',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 5, 2.0, 10, 6.0, 14, 10.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'motorway'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-trunk-casing',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#C9A000',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 6, 1.5, 10, 5.5, 14, 9.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'trunk'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-primary-casing',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#BBBBBB',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 7, 1.5, 10, 5.0, 14, 8.5,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'primary'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-secondary-casing',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#C4C4C4',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 9, 1.0, 12, 4.0, 14, 7.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: [
          'in', ['get', 'class'], ['literal', ['secondary', 'tertiary']],
        ],
      );

      // Road fills
      await c.addLineLayer(
        'openmaptiles',
        'road-motorway',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#FFA726',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 5, 1.0, 10, 4.0, 14, 7.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'motorway'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-trunk',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#FFD54F',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 6, 1.0, 10, 3.5, 14, 6.5,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'trunk'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-primary',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#FFFFFF',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 7, 0.8, 10, 3.0, 14, 6.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'primary'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-secondary',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#FFFFFF',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 9, 0.6, 12, 2.5, 14, 5.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'secondary'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-tertiary',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#F5F5F5',
          lineWidth: [
            'interpolate', ['linear'], ['zoom'], 10, 0.4, 12, 2.0, 14, 4.0,
          ],
        ),
        sourceLayer: 'transportation',
        filter: ['==', ['get', 'class'], 'tertiary'],
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-minor',
        const LineLayerProperties(
          lineCap: 'round',
          lineColor: '#EEEEEE',
          lineWidth: ['interpolate', ['linear'], ['zoom'], 12, 0.3, 14, 2.0],
        ),
        sourceLayer: 'transportation',
        filter: [
          'in', ['get', 'class'], ['literal', ['minor', 'service', 'track']],
        ],
        minzoom: 12,
      );
      await c.addLineLayer(
        'openmaptiles',
        'road-path',
        const LineLayerProperties(
          lineColor: '#C8B89A',
          lineWidth: 1.0,
          lineDasharray: [2, 2],
        ),
        sourceLayer: 'transportation',
        filter: [
          'in', ['get', 'class'],
          ['literal', ['path', 'pedestrian', 'cycleway']],
        ],
        minzoom: 13,
      );

      // Admin boundaries
      await c.addLineLayer(
        'openmaptiles',
        'boundary-country',
        const LineLayerProperties(
          lineColor: '#9E9E9E',
          lineWidth: 1.5,
          lineDasharray: [4, 3],
        ),
        sourceLayer: 'boundary',
        filter: ['==', ['get', 'admin_level'], 2],
      );
      await c.addLineLayer(
        'openmaptiles',
        'boundary-state',
        const LineLayerProperties(
          lineColor: '#BDBDBD',
          lineWidth: 1.0,
          lineDasharray: [3, 3],
        ),
        sourceLayer: 'boundary',
        filter: ['==', ['get', 'admin_level'], 4],
        minzoom: 6,
      );

      // Labels
      await c.addSymbolLayer(
        'openmaptiles',
        'road-name',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 10,
          symbolPlacement: 'line',
          textMaxAngle: 30,
          textColor: '#555555',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'transportation_name',
        minzoom: 12,
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'water-name',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 11,
          symbolPlacement: 'point',
          textColor: '#3A7FC1',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'water_name',
        minzoom: 10,
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'waterway-name',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 10,
          symbolPlacement: 'line',
          textColor: '#3A7FC1',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'waterway',
        minzoom: 13,
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'park-name',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 11,
          symbolPlacement: 'point',
          textColor: '#2E7D32',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'park',
        minzoom: 12,
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'poi-label',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 11,
          textMaxWidth: 8,
          textAnchor: 'top',
          textOffset: [0, 0.5],
          textColor: '#333333',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'poi',
        minzoom: 14,
        filter: ['<=', ['get', 'rank'], 3],
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'place-suburb',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: 12,
          textTransform: 'uppercase',
          textLetterSpacing: 0.1,
          textColor: '#757575',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.5,
        ),
        sourceLayer: 'place',
        minzoom: 11,
        filter: [
          'in', ['get', 'class'],
          ['literal', ['suburb', 'neighbourhood', 'quarter']],
        ],
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'place-town',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: ['interpolate', ['linear'], ['zoom'], 8, 11, 12, 14],
          textColor: '#333333',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.0,
        ),
        sourceLayer: 'place',
        minzoom: 8,
        filter: [
          'in', ['get', 'class'], ['literal', ['village', 'town']],
        ],
      );
      await c.addSymbolLayer(
        'openmaptiles',
        'place-city',
        const SymbolLayerProperties(
          textFont: ['Noto Sans Regular'],
          textField: _nameExpr,
          textSize: [
            'interpolate', ['linear'], ['zoom'], 4, 10, 8, 16, 12, 20,
          ],
          textColor: '#1A1A1A',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2.5,
        ),
        sourceLayer: 'place',
        minzoom: 4,
        filter: [
          'in', ['get', 'class'], ['literal', ['city', 'capital']],
        ],
      );
    } else if (!isOffline) {
      await c.addSource(
        'open-tiles',
        const RasterSourceProperties(
          tiles: [
            'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
            'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
            'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          ],
        ),
      );
      await c.addRasterLayer(
        'open-tiles',
        'base-tiles',
        const RasterLayerProperties(),
        minzoom: 0,
        maxzoom: 14,
      );
    } else if (isOffline &&
        worldBasemapUrl != null &&
        worldBasemapUrl.isNotEmpty) {
      // No pack active and no internet for the raster fallback — show the
      // bundled world overview (country outlines + coastlines rendered as
      // raster PNG tiles, zoom 0-6, built from Natural Earth 1:110m data)
      // instead of a blank background, so there's always something on
      // screen. Raster tiles, not vector — city labels are a separate
      // plain-GeoJSON overlay (same proven-reliable pattern as the
      // landmarks layer) rather than a vector-tile source, sidestepping
      // the vector-tile source-layer rendering issues entirely.
      await c.addSource(
        'world-basemap',
        RasterSourceProperties(
          tiles: ['$worldBasemapUrl/{z}/{x}/{y}.png'],
          minzoom: 0,
          maxzoom: 6,
        ),
      );
      await c.addRasterLayer(
        'world-basemap',
        'world-basemap-layer',
        const RasterLayerProperties(),
        minzoom: 0,
        maxzoom: 6,
      );

      try {
        final placesRaw = await rootBundle.loadString(
          'assets/world_basemap/places.geojson',
        );
        final placesGeoJson = jsonDecode(placesRaw) as Map<String, dynamic>;
        await c.addGeoJsonSource('world-places', placesGeoJson);
        await c.addSymbolLayer(
          'world-places',
          'world-places-label',
          const SymbolLayerProperties(
            textFont: ['Noto Sans Regular'],
            textField: '{name}',
            textSize: 11,
            textColor: '#555555',
            textHaloColor: '#F2EFE9',
            textHaloWidth: 1.5,
          ),
        );
      } catch (e) {
        debugPrint('[LayerEngine] Failed to load world basemap place labels: $e');
      }
    }
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
        textFont: ['Noto Sans Regular'],
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
