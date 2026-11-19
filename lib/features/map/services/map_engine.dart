import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/config/map_basemap_config.dart';
import '../../../core/config/map_basemap_style.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/position_opinion.dart';

class TileEngine {
  /// Generate the base MapLibre style JSON.
  ///
  /// When [includeRasterBasemap] is true (no offline pack), the light OSM
  /// raster source/layer is embedded so streets paint on first style load
  /// instead of waiting for imperative setup. Local vector MBTiles packs
  /// still use an empty style + imperative layers — embedding those does
  /// not render reliably in this maplibre_gl version.
  Map<String, dynamic> generateStyle({
    String? glyphsUrl,
    bool includeRasterBasemap = true,
    String? rasterCacheUrl,
    bool satellite = false,
    MapBasemapStyle? basemapStyle,
  }) {
    // ignore: deprecated_member_use_from_same_package
    final style = basemapStyle ??
        (satellite ? MapBasemapStyle.satellite : MapBasemapStyle.street);
    final sources = <String, dynamic>{};
    final layers = <Map<String, dynamic>>[
      {
        'id': 'background',
        'type': 'background',
        'paint': {
          'background-color': MapBasemapConfig.backgroundColor(style),
        },
      },
    ];

    if (includeRasterBasemap) {
      final provider = MapBasemapConfig.cacheProviderPath(style);
      final List<String> tiles;
      if (rasterCacheUrl != null && rasterCacheUrl.isNotEmpty) {
        final path = provider == 'streets'
            ? '$rasterCacheUrl/{z}/{x}/{y}.png'
            : '$rasterCacheUrl/$provider/{z}/{x}/{y}.png';
        tiles = [path];
      } else {
        tiles = MapBasemapConfig.directTileUrls(style);
      }
      sources['open-tiles'] = {
        'type': 'raster',
        'tiles': tiles,
        'tileSize': MapBasemapConfig.tileSize,
        'maxzoom': MapBasemapConfig.sourceMaxZoom,
        'attribution': MapBasemapConfig.attributionFor(style),
      };
      layers.add({
        'id': 'base-tiles',
        'type': 'raster',
        'source': 'open-tiles',
        'minzoom': 0,
        'maxzoom': MapBasemapConfig.layerMaxZoom,
      });

      // Hybrid: imagery + Esri place labels (second raster).
      if (style == MapBasemapStyle.hybrid) {
        final labelTiles = (rasterCacheUrl != null && rasterCacheUrl.isNotEmpty)
            ? ['$rasterCacheUrl/labels/{z}/{x}/{y}.png']
            : [
                'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/'
                    'World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
              ];
        sources['label-tiles'] = {
          'type': 'raster',
          'tiles': labelTiles,
          'tileSize': MapBasemapConfig.tileSize,
          'maxzoom': MapBasemapConfig.sourceMaxZoom,
        };
        layers.add({
          'id': 'label-tiles',
          'type': 'raster',
          'source': 'label-tiles',
          'minzoom': 0,
          'maxzoom': MapBasemapConfig.layerMaxZoom,
          'paint': {'raster-opacity': 0.95},
        });
      }
    }

    return {
      'version': 8,
      'name': 'WHAMI ${style.label}',
      'sources': sources,
      'layers': layers,
      // Local GlyphServer when assets exist; otherwise public MapLibre fonts
      // so opinion / crossfire labels still paint (bundled glyphs are often
      // missing → local server 404s and text never appears).
      'glyphs': (glyphsUrl != null && glyphsUrl.isNotEmpty)
          ? '$glyphsUrl/{fontstack}/{range}.pbf'
          : 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
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

  static const _baseMapLayerIds = [
    'water', 'waterway',
    'landcover-base', 'landcover-grass', 'landcover-wood',
    'landuse-base', 'landuse-park', 'landuse-residential', 'landuse-commercial',
    'park-fill', 'building',
    'transportation-base',
    'road-motorway-casing', 'road-trunk-casing', 'road-primary-casing',
    'road-secondary-casing', 'road-tertiary-casing', 'road-minor-casing',
    'road-motorway', 'road-trunk', 'road-primary', 'road-secondary',
    'road-tertiary', 'road-minor', 'road-path',
    'boundary-country', 'boundary-state',
    'road-name', 'water-name', 'waterway-name', 'park-name', 'poi-label',
    'place-suburb', 'place-town', 'place-city',
    'base-tiles',
  ];

  /// Runs [action], logging and swallowing any failure instead of letting it
  /// propagate. Each base-map layer/source is added one native platform-
  /// channel call at a time (see setupBaseMapLayers doc comment for why),
  /// and the native side (MapLibreMapController.java's addLineLayer/
  /// addFillLayer/addSymbolLayer) calls style.addLayer() with no try/catch
  /// of its own — if a layer id already exists, or the style transiently
  /// isn't ready, that one call throws and — without this wrapper — every
  /// later call in the same setupBaseMapLayers() invocation would never run
  /// at all, since they're all plain sequential awaits with a single outer
  /// try/catch far above. That silent cascade (not filter/schema mismatches)
  /// was the actual cause of roads/landuse/buildings intermittently going
  /// missing: whichever layer happened to fail first determined everything
  /// rendered after it. Isolating each call means one bad layer just logs
  /// and skips instead of blanking out the rest of the map.
  Future<void> _safeAdd(String label, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[LayerEngine] Failed to add $label: $e');
    }
  }

  /// Removes every base-map layer/source id before (re)adding them, so a
  /// retry (e.g. onStyleLoadedCallback firing more than once for one
  /// logical style load, per the existing note below) starts from a clean
  /// slate instead of immediately failing on "already exists" for whatever
  /// a previous partial run managed to add — which, before _safeAdd existed,
  /// meant a retry's very first call could fail and abort the entire retry
  /// too, freezing the map in a partial state permanently.
  Future<void> _clearBaseMapLayers({bool preserveRaster = false}) async {
    final c = _controller;
    if (c == null) return;
    for (final id in _baseMapLayerIds) {
      if (preserveRaster && id == 'base-tiles') continue;
      try {
        await c.removeLayer(id);
      } catch (_) {}
    }
    try {
      await c.removeSource('openmaptiles');
    } catch (_) {}
    if (!preserveRaster) {
      try {
        await c.removeSource('open-tiles');
      } catch (_) {}
    }
  }

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
  ///
  /// Every add call below goes through _safeAdd and _clearBaseMapLayers()
  /// runs first — see those doc comments for why: without them, one failed
  /// layer used to silently take every layer scheduled after it down with
  /// it, which is what made roads/landuse/buildings look randomly
  /// incomplete rather than consistently present or consistently absent.
  Future<void> setupBaseMapLayers({
    // Only consulted when no pack is active (localMBTilesUrl is empty) and
    // rasterCacheUrl isn't ready yet — the local vector tile source used
    // when a pack IS active never reads this, since it's served from the
    // loopback MBTiles server regardless of real connectivity.
    required bool isOffline,
    String? localMBTilesUrl,
    String? rasterCacheUrl,
    /// When true, the light OSM raster was already baked into the style JSON
    /// — skip clear/re-add for the no-pack path so streets stay visible.
    bool rasterAlreadyInStyle = false,
    bool satellite = false,
    MapBasemapStyle? basemapStyle,
  }) async {
    final style = basemapStyle ??
        (satellite ? MapBasemapStyle.satellite : MapBasemapStyle.street);
    final c = _controller;
    if (c == null) return;

    final hasLocalTiles =
        localMBTilesUrl != null && localMBTilesUrl.isNotEmpty;

    // Online default basemap is already in the style JSON. Clearing first
    // then returning left a blank beige map (client OSM complaint).
    if (!hasLocalTiles && rasterAlreadyInStyle) return;

    // Keep online streets under pack vector layers so the map never goes
    // blank if MBTiles fail or while vector tiles are loading.
    await _clearBaseMapLayers(preserveRaster: rasterAlreadyInStyle);

    if (hasLocalTiles) {
      await _safeAdd(
        'openmaptiles source',
        () => c.addSource(
          'openmaptiles',
          VectorSourceProperties(
            tiles: ['$localMBTilesUrl/{z}/{x}/{y}.pbf'],
            minzoom: 0,
            maxzoom: 14,
          ),
        ),
      );

      await _safeAdd(
        'water',
        () => c.addFillLayer(
          'openmaptiles',
          'water',
          const FillLayerProperties(fillColor: '#A8D1E7', fillOpacity: 0.9),
          sourceLayer: 'water',
        ),
      );
      await _safeAdd(
        'waterway',
        () => c.addLineLayer(
          'openmaptiles',
          'waterway',
          const LineLayerProperties(
            lineColor: '#7EC8E3',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 8, 0.5, 12, 2.0, 14, 3.0,
            ],
          ),
          sourceLayer: 'waterway',
        ),
      );

      // Catch-all landcover/landuse fills, UNFILTERED, drawn before the
      // specific-colored ones below. Real pack data (verified against a
      // Planetiler/OpenMapTiles-schema pack) carries many more class values
      // than the specific filters here cover (landuse alone: neighbourhood,
      // school, college, cemetery, hospital, library, suburb, ... beyond
      // just park/residential/commercial) — without a catch-all underneath,
      // every one of those un-listed classes renders nothing at all instead
      // of just an unstyled/generic fill.
      await _safeAdd(
        'landcover-base',
        () => c.addFillLayer(
          'openmaptiles',
          'landcover-base',
          const FillLayerProperties(fillColor: '#E3ECD9', fillOpacity: 0.5),
          sourceLayer: 'landcover',
        ),
      );
      await _safeAdd(
        'landcover-grass',
        () => c.addFillLayer(
          'openmaptiles',
          'landcover-grass',
          const FillLayerProperties(fillColor: '#D4EDBC', fillOpacity: 0.8),
          sourceLayer: 'landcover',
          filter: ['==', ['get', 'class'], 'grass'],
        ),
      );
      await _safeAdd(
        'landcover-wood',
        () => c.addFillLayer(
          'openmaptiles',
          'landcover-wood',
          const FillLayerProperties(fillColor: '#BDDFAD', fillOpacity: 0.75),
          sourceLayer: 'landcover',
          filter: ['==', ['get', 'class'], 'wood'],
        ),
      );
      await _safeAdd(
        'landuse-base',
        () => c.addFillLayer(
          'openmaptiles',
          'landuse-base',
          const FillLayerProperties(fillColor: '#EDEAE3', fillOpacity: 0.5),
          sourceLayer: 'landuse',
        ),
      );
      await _safeAdd(
        'landuse-park',
        () => c.addFillLayer(
          'openmaptiles',
          'landuse-park',
          const FillLayerProperties(fillColor: '#C8E6C0', fillOpacity: 0.85),
          sourceLayer: 'landuse',
          filter: [
            'in', ['get', 'class'],
            ['literal', ['park', 'pitch', 'recreation_ground', 'garden']],
          ],
        ),
      );
      await _safeAdd(
        'landuse-residential',
        () => c.addFillLayer(
          'openmaptiles',
          'landuse-residential',
          const FillLayerProperties(fillColor: '#EBEBEB', fillOpacity: 0.6),
          sourceLayer: 'landuse',
          filter: ['==', ['get', 'class'], 'residential'],
        ),
      );
      await _safeAdd(
        'landuse-commercial',
        () => c.addFillLayer(
          'openmaptiles',
          'landuse-commercial',
          const FillLayerProperties(fillColor: '#F5DEB3', fillOpacity: 0.5),
          sourceLayer: 'landuse',
          filter: [
            'in', ['get', 'class'],
            ['literal', ['commercial', 'retail', 'industrial']],
          ],
        ),
      );
      await _safeAdd(
        'park-fill',
        () => c.addFillLayer(
          'openmaptiles',
          'park-fill',
          const FillLayerProperties(fillColor: '#C8E6C0', fillOpacity: 0.7),
          sourceLayer: 'park',
        ),
      );
      await _safeAdd(
        'building',
        () => c.addFillLayer(
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
        ),
      );

      // Catch-all transportation line, UNFILTERED, drawn before the casings
      // below — same reasoning as the landcover/landuse catch-alls: schema
      // classes exist (e.g. 'rail') that none of the specific class filters
      // below match, so without this they'd render as nothing rather than
      // a plain line.
      await _safeAdd(
        'transportation-base',
        () => c.addLineLayer(
          'openmaptiles',
          'transportation-base',
          const LineLayerProperties(
            lineCap: 'round',
            // Deliberately darker than the near-white road fills below —
            // this is a floor for classes none of them match (e.g. 'rail'),
            // so it needs to read against the #F2EFE9 background on its
            // own rather than relying on a casing underneath it.
            lineColor: '#ADADA5',
            lineWidth: ['interpolate', ['linear'], ['zoom'], 8, 0.5, 14, 2.0],
          ),
          sourceLayer: 'transportation',
        ),
      );

      // Road casings (drawn first so fills appear on top)
      await _safeAdd(
        'road-motorway-casing',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-trunk-casing',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-primary-casing',
        () => c.addLineLayer(
          'openmaptiles',
          'road-primary-casing',
          const LineLayerProperties(
            lineCap: 'round',
            // Darkened from #BBBBBB — that was nearly the same lightness as
            // the #F2EFE9 background/#EBEBEB residential fill, so the white
            // road fill it's supposed to outline had no visible border and
            // read as "faded"/invisible.
            lineColor: '#8F8F8F',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 7, 1.5, 10, 5.0, 14, 8.5,
            ],
          ),
          sourceLayer: 'transportation',
          filter: ['==', ['get', 'class'], 'primary'],
        ),
      );
      await _safeAdd(
        'road-secondary-casing',
        () => c.addLineLayer(
          'openmaptiles',
          'road-secondary-casing',
          const LineLayerProperties(
            lineCap: 'round',
            lineColor: '#A0A0A0',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 9, 1.0, 12, 4.0, 14, 7.0,
            ],
          ),
          sourceLayer: 'transportation',
          filter: ['==', ['get', 'class'], 'secondary'],
        ),
      );
      await _safeAdd(
        'road-tertiary-casing',
        () => c.addLineLayer(
          'openmaptiles',
          'road-tertiary-casing',
          const LineLayerProperties(
            lineCap: 'round',
            // Tertiary and minor previously had NO casing at all — just a
            // near-white fill directly on the near-white background, which
            // made them essentially invisible. Same casing/fill technique
            // as the tiers above now, just thinner.
            lineColor: '#B5B5B0',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 10, 0.8, 12, 2.8, 14, 5.2,
            ],
          ),
          sourceLayer: 'transportation',
          filter: ['==', ['get', 'class'], 'tertiary'],
        ),
      );
      await _safeAdd(
        'road-minor-casing',
        () => c.addLineLayer(
          'openmaptiles',
          'road-minor-casing',
          const LineLayerProperties(
            lineCap: 'round',
            lineColor: '#C2C2BC',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 12, 0.6, 14, 2.8,
            ],
          ),
          sourceLayer: 'transportation',
          filter: [
            'in', ['get', 'class'], ['literal', ['minor', 'service', 'track']],
          ],
          minzoom: 12,
        ),
      );

      // Road fills
      await _safeAdd(
        'road-motorway',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-trunk',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-primary',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-secondary',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-tertiary',
        () => c.addLineLayer(
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
        ),
      );
      await _safeAdd(
        'road-minor',
        () => c.addLineLayer(
          'openmaptiles',
          'road-minor',
          const LineLayerProperties(
            lineCap: 'round',
            lineColor: '#EEEEEE',
            lineWidth: [
              'interpolate', ['linear'], ['zoom'], 12, 0.3, 14, 2.0,
            ],
          ),
          sourceLayer: 'transportation',
          filter: [
            'in', ['get', 'class'],
            ['literal', ['minor', 'service', 'track']],
          ],
          minzoom: 12,
        ),
      );
      await _safeAdd(
        'road-path',
        () => c.addLineLayer(
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
        ),
      );

      // Admin boundaries
      await _safeAdd(
        'boundary-country',
        () => c.addLineLayer(
          'openmaptiles',
          'boundary-country',
          const LineLayerProperties(
            lineColor: '#9E9E9E',
            lineWidth: 1.5,
            lineDasharray: [4, 3],
          ),
          sourceLayer: 'boundary',
          filter: ['==', ['get', 'admin_level'], 2],
        ),
      );
      await _safeAdd(
        'boundary-state',
        () => c.addLineLayer(
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
        ),
      );

      // Labels
      await _safeAdd(
        'road-name',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'water-name',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'waterway-name',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'park-name',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'poi-label',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'place-suburb',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'place-town',
        () => c.addSymbolLayer(
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
        ),
      );
      await _safeAdd(
        'place-city',
        () => c.addSymbolLayer(
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
        ),
      );
    } else if (!rasterAlreadyInStyle) {
      // No pack active — raster basemap (only when not already in style JSON).
      if (rasterCacheUrl != null && rasterCacheUrl.isNotEmpty) {
        final provider = MapBasemapConfig.cacheProviderPath(style);
        final tiles = provider == 'streets'
            ? ['$rasterCacheUrl/{z}/{x}/{y}.png']
            : ['$rasterCacheUrl/$provider/{z}/{x}/{y}.png'];
        await _safeAdd(
          'open-tiles source',
          () => c.addSource(
            'open-tiles',
            RasterSourceProperties(
              tiles: tiles,
              tileSize: MapBasemapConfig.tileSize,
              maxzoom: MapBasemapConfig.sourceMaxZoom,
            ),
          ),
        );
        await _safeAdd(
          'base-tiles',
          () => c.addRasterLayer(
            'open-tiles',
            'base-tiles',
            const RasterLayerProperties(),
            minzoom: 0,
            maxzoom: MapBasemapConfig.layerMaxZoom,
          ),
        );
      } else if (!isOffline) {
        await _safeAdd(
          'open-tiles source',
          () => c.addSource(
            'open-tiles',
            RasterSourceProperties(
              tiles: MapBasemapConfig.tileUrls,
              tileSize: MapBasemapConfig.tileSize,
              maxzoom: MapBasemapConfig.sourceMaxZoom,
            ),
          ),
        );
        await _safeAdd(
          'base-tiles',
          () => c.addRasterLayer(
            'open-tiles',
            'base-tiles',
            const RasterLayerProperties(),
            minzoom: 0,
            maxzoom: MapBasemapConfig.layerMaxZoom,
          ),
        );
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
    await _safeAdd('landmarks source', () => c.addGeoJsonSource('landmarks', landmarksGeo));
    await _safeAdd(
      'landmark-layer',
      () => c.addSymbolLayer(
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
      ),
    );

    // Add Magnetic circle layer
    await _safeAdd('magnetic source', () => c.addGeoJsonSource('magnetic', magneticGeo));
    await _safeAdd(
      'magnetic-layer',
      () => c.addCircleLayer(
        'magnetic',
        'magnetic-layer',
        const CircleLayerProperties(
          circleRadius: 5.0,
          circleColor: '#E24B4A',
          circleOpacity: 0.6,
        ),
      ),
    );

    // Add Seamap line layer
    await _safeAdd('seamap source', () => c.addGeoJsonSource('seamap', seamapGeo));
    await _safeAdd(
      'seamap-layer',
      () => c.addLineLayer(
        'seamap',
        'seamap-layer',
        const LineLayerProperties(lineColor: '#00E5FF', lineWidth: 3.0),
      ),
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

  /// Fit both ghost and trusted pins in view (one-shot spoof reveal).
  void fitPair(
    double lat1,
    double lng1,
    double lat2,
    double lng2, {
    double padding = 64,
  }) {
    final c = _controller;
    if (c == null) return;
    final sw = LatLng(
      lat1 < lat2 ? lat1 : lat2,
      lng1 < lng2 ? lng1 : lng2,
    );
    final ne = LatLng(
      lat1 > lat2 ? lat1 : lat2,
      lng1 > lng2 ? lng1 : lng2,
    );
    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        left: padding,
        top: padding,
        right: padding,
        bottom: padding,
      ),
    );
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

  bool _opinionsReady = false;
  bool _liveGpsReady = false;
  bool _ghostLayersReady = false;
  bool _crossfireReady = false;
  bool _flightPlanReady = false;
  bool _rangeRingsReady = false;
  bool _truthTrailsReady = false;
  bool _spoofHeatReady = false;

  /// Serializes source/layer creation so concurrent draws don't race
  /// (STYLE_NOT_READY → source missing → Layer already exists spam).
  Future<void> _setupLock = Future.value();

  Future<T> _withSetupLock<T>(Future<T> Function() fn) {
    final previous = _setupLock;
    late final Future<T> next;
    next = previous.catchError((_) {}).then((_) => fn());
    _setupLock = next.then((_) {}, onError: (_) {});
    return next;
  }

  bool _isAlreadyExists(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('already exists') || s.contains('source already');
  }

  bool _isStyleNotReady(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('style_not_ready') ||
        s.contains('style is null') ||
        s.contains('not fully loaded');
  }

  Future<bool> _ensureGeoJsonSource(
    MapLibreMapController c,
    String sourceId,
    Map<String, dynamic> geo,
  ) async {
    try {
      await c.addGeoJsonSource(sourceId, geo);
      return true;
    } catch (e) {
      if (_isAlreadyExists(e)) {
        try {
          await c.setGeoJsonSource(sourceId, geo);
          return true;
        } catch (_) {
          return true; // source exists; layers may still need add
        }
      }
      if (_isStyleNotReady(e)) return false;
      // Source missing or other — try set (won't work if absent).
      try {
        await c.setGeoJsonSource(sourceId, geo);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// addXLayer; "already exists" counts as success.
  Future<bool> _tryAddLayer(Future<void> Function() add) async {
    try {
      await add();
      return true;
    } catch (e) {
      if (_isAlreadyExists(e)) return true;
      if (!_isStyleNotReady(e)) {
        debugPrint('[OverlayEngine] addLayer: $e');
      }
      return false;
    }
  }

  Future<void> _clearSourceIfReady(
    MapLibreMapController c,
    String sourceId,
    bool ready,
  ) async {
    if (!ready) return;
    try {
      await c.setGeoJsonSource(sourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });
    } catch (_) {}
  }

  /// Draw consensus position opinions onto the map (GeoJSON — no AnnotationManager).
  Future<void> drawOpinions(
    List<PositionOpinion> opinions,
    bool visible,
  ) async {
    final c = _controller;
    if (c == null) return;

    final features = <Map<String, dynamic>>[];
    if (visible) {
      for (final op in opinions) {
        if (op.confidence == 0 || op.status == 'unavailable') continue;
        if (op.latitude == 0 && op.longitude == 0) continue;
        // Skip raw GPS here — [drawLiveGps] owns the blue puck.
        if (op.sourceType == 'gps') continue;
        final color = _colorForSource(op.sourceType);
        final hex =
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        features.add({
          'type': 'Feature',
          'properties': {
            'label': op.shortCode,
            'color': hex,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [op.longitude, op.latitude],
          },
        });
      }
    }

    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_opinionsReady) {
          final ok = await _ensureGeoJsonSource(c, 'opinions-overlay', geo);
          if (!ok) return;
          final circles = await _tryAddLayer(
            () => c.addCircleLayer(
              'opinions-overlay',
              'opinions-circles',
              const CircleLayerProperties(
                circleRadius: 9,
                circleColor: '#FFC107',
                circleOpacity: 0.9,
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2,
              ),
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              'opinions-overlay',
              'opinions-labels',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 11,
                textColor: '#0A1628',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.4,
                textOffset: [0.0, 1.15],
                textFont: ['Noto Sans Regular'],
              ),
            ),
          );
          if (circles) _opinionsReady = true;
        } else {
          await c.setGeoJsonSource('opinions-overlay', geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawOpinions failed: $e');
        _opinionsReady = false;
      }
    });
  }

  /// Blue GPS puck + accuracy halo (replaces native myLocation on iOS).
  Future<void> drawLiveGps({
    required double lat,
    required double lng,
    required double accuracyM,
  }) async {
    final c = _controller;
    if (c == null) return;

    final haloPx = (accuracyM / 3).clamp(16.0, 56.0);
    final geo = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'kind': 'halo', 'r': haloPx},
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
        },
        {
          'type': 'Feature',
          'properties': {'kind': 'dot', 'label': 'G'},
          'geometry': {
            'type': 'Point',
            'coordinates': [lng, lat],
          },
        },
      ],
    };

    await _withSetupLock(() async {
      try {
        if (!_liveGpsReady) {
          final ok = await _ensureGeoJsonSource(c, 'live-gps', geo);
          if (!ok) return;
          final halo = await _tryAddLayer(
            () => c.addCircleLayer(
              'live-gps',
              'live-gps-halo',
              const CircleLayerProperties(
                circleRadius: 28,
                circleColor: '#2196F3',
                circleOpacity: 0.22,
                circleStrokeColor: '#2196F3',
                circleStrokeWidth: 1,
                circleStrokeOpacity: 0.45,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'halo',
              ],
            ),
          );
          final dot = await _tryAddLayer(
            () => c.addCircleLayer(
              'live-gps',
              'live-gps-dot',
              const CircleLayerProperties(
                circleRadius: 10,
                circleColor: '#2196F3',
                circleOpacity: 1,
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 3,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'dot',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              'live-gps',
              'live-gps-label',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 11,
                textColor: '#0A1628',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.2,
                textOffset: [0.0, 1.3],
                textFont: ['Noto Sans Regular'],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'dot',
              ],
            ),
          );
          if (halo && dot) _liveGpsReady = true;
        } else {
          await c.setGeoJsonSource('live-gps', geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawLiveGps failed: $e');
        _liveGpsReady = false;
      }
    });
  }

  void resetOpinionLayers() {
    _opinionsReady = false;
    _liveGpsReady = false;
  }

  /// Ghost pin (GPS claim) + solid trusted pin + red lie line.
  Future<void> drawGhostLie({
    required bool visible,
    double? gpsLat,
    double? gpsLng,
    double? trustedLat,
    double? trustedLng,
    double? lieDistanceM,
  }) async {
    final c = _controller;
    if (c == null) return;

    if (!visible ||
        gpsLat == null ||
        gpsLng == null ||
        trustedLat == null ||
        trustedLng == null) {
      await _clearSourceIfReady(c, 'ghost-lie', _ghostLayersReady);
      return;
    }

    final distLabel = lieDistanceM == null
        ? 'GPS claim'
        : lieDistanceM >= 1000
            ? 'GPS is ${(lieDistanceM / 1000).toStringAsFixed(1)} km from reality'
            : 'GPS is ${lieDistanceM.round()} m from reality';

    final geo = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'kind': 'line', 'label': distLabel},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [gpsLng, gpsLat],
              [trustedLng, trustedLat],
            ],
          },
        },
        {
          'type': 'Feature',
          'properties': {'kind': 'ghost', 'label': 'GPS'},
          'geometry': {
            'type': 'Point',
            'coordinates': [gpsLng, gpsLat],
          },
        },
        {
          'type': 'Feature',
          'properties': {'kind': 'trusted', 'label': 'REAL'},
          'geometry': {
            'type': 'Point',
            'coordinates': [trustedLng, trustedLat],
          },
        },
        {
          'type': 'Feature',
          'properties': {'kind': 'label', 'label': distLabel},
          'geometry': {
            'type': 'Point',
            'coordinates': [
              (gpsLng + trustedLng) / 2,
              (gpsLat + trustedLat) / 2,
            ],
          },
        },
      ],
    };

    await _withSetupLock(() async {
      try {
        if (!_ghostLayersReady) {
          final ok = await _ensureGeoJsonSource(c, 'ghost-lie', geo);
          if (!ok) return;
          final line = await _tryAddLayer(
            () => c.addLineLayer(
              'ghost-lie',
              'ghost-lie-line',
              const LineLayerProperties(
                lineColor: '#E53935',
                lineWidth: 3.0,
                lineOpacity: 0.9,
                lineDasharray: [2.0, 1.5],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'line',
              ],
            ),
          );
          final ghost = await _tryAddLayer(
            () => c.addCircleLayer(
              'ghost-lie',
              'ghost-lie-ghost',
              const CircleLayerProperties(
                circleRadius: 14,
                circleColor: '#90CAF9',
                circleOpacity: 0.35,
                circleStrokeColor: '#1565C0',
                circleStrokeWidth: 2,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'ghost',
              ],
            ),
          );
          final trusted = await _tryAddLayer(
            () => c.addCircleLayer(
              'ghost-lie',
              'ghost-lie-trusted',
              const CircleLayerProperties(
                circleRadius: 11,
                circleColor: '#43A047',
                circleOpacity: 0.95,
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2.5,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'trusted',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              'ghost-lie',
              'ghost-lie-label',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 11,
                textColor: '#B71C1C',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.5,
                textOffset: [0.0, -1.4],
                textFont: ['Noto Sans Regular'],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'label',
              ],
            ),
          );
          if (line && ghost && trusted) _ghostLayersReady = true;
        } else {
          await c.setGeoJsonSource('ghost-lie', geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawGhostLie failed: $e');
        _ghostLayersReady = false;
      }
    });
  }

  void resetGhostLayers() {
    _ghostLayersReady = false;
  }

  /// Arrows from trusted reality to each witness claim (agree = green, outlier = red).
  Future<void> drawCrossfire({
    required bool visible,
    required double trustedLat,
    required double trustedLng,
    required List<({
      String id,
      double lat,
      double lng,
      bool agrees,
      bool isOutlier,
      String shortCode,
    })> witnesses,
  }) async {
    final c = _controller;
    if (c == null) return;

    if (!visible || witnesses.isEmpty) {
      await _clearSourceIfReady(c, 'crossfire', _crossfireReady);
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final w in witnesses) {
      // Skip near-zero arrows (witness pinned on trusted).
      final same = (w.lat - trustedLat).abs() < 1e-6 &&
          (w.lng - trustedLng).abs() < 1e-6;
      if (same) continue;
      final kind = w.isOutlier
          ? 'outlier'
          : w.agrees
              ? 'agree'
              : 'soft';
      features.add({
        'type': 'Feature',
        'properties': {'kind': kind, 'label': w.shortCode},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [trustedLng, trustedLat],
            [w.lng, w.lat],
          ],
        },
      });
      features.add({
        'type': 'Feature',
        'properties': {'kind': '${kind}_pt', 'label': w.shortCode},
        'geometry': {
          'type': 'Point',
          'coordinates': [w.lng, w.lat],
        },
      });
    }

    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_crossfireReady) {
          final ok = await _ensureGeoJsonSource(c, 'crossfire', geo);
          if (!ok) return;
          final agree = await _tryAddLayer(
            () => c.addLineLayer(
              'crossfire',
              'crossfire-agree',
              const LineLayerProperties(
                lineColor: '#43A047',
                lineWidth: 2.5,
                lineOpacity: 0.85,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'agree',
              ],
            ),
          );
          final outlier = await _tryAddLayer(
            () => c.addLineLayer(
              'crossfire',
              'crossfire-outlier',
              const LineLayerProperties(
                lineColor: '#E53935',
                lineWidth: 3.0,
                lineOpacity: 0.95,
                lineDasharray: [1.5, 1.2],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'outlier',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addLineLayer(
              'crossfire',
              'crossfire-soft',
              const LineLayerProperties(
                lineColor: '#B28704',
                lineWidth: 2.0,
                lineOpacity: 0.75,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'soft',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              'crossfire',
              'crossfire-labels',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 11,
                textColor: '#FFFFFF',
                textHaloColor: '#0A1628',
                textHaloWidth: 1.5,
                textOffset: [0.0, -1.2],
                textFont: ['Noto Sans Regular'],
              ),
              filter: [
                'in',
                ['get', 'kind'],
                [
                  'literal',
                  ['agree_pt', 'outlier_pt', 'soft_pt']
                ],
              ],
            ),
          );
          if (agree && outlier) _crossfireReady = true;
        } else {
          await c.setGeoJsonSource('crossfire', geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawCrossfire failed: $e');
        _crossfireReady = false;
      }
    });
  }

  void resetCrossfireLayers() {
    _crossfireReady = false;
  }

  /// Premium travel-route overlay: casing + cyan track, role-colored pins.
  Future<void> drawFlightPlan({
    required bool visible,
    required List<({String id, String name, double lat, double lng})> waypoints,
    double? progressLat,
    double? progressLng,
  }) async {
    final c = _controller;
    if (c == null) return;
    const sourceId = 'travel-route';

    if (!visible || waypoints.isEmpty) {
      await _clearSourceIfReady(c, sourceId, _flightPlanReady);
      return;
    }

    final features = <Map<String, dynamic>>[];
    if (waypoints.length >= 2) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'route'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final w in waypoints) [w.lng, w.lat],
          ],
        },
      });
    }
    for (var i = 0; i < waypoints.length; i++) {
      final w = waypoints[i];
      final role = i == 0
          ? 'origin'
          : (i == waypoints.length - 1 && waypoints.length > 1)
              ? 'destination'
              : 'enroute';
      final idx = (i + 1).toString().padLeft(2, '0');
      features.add({
        'type': 'Feature',
        'properties': {
          'kind': 'waypoint',
          'role': role,
          'label': '$idx  ${w.name}',
          'index': i + 1,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [w.lng, w.lat],
        },
      });
    }
    if (progressLat != null && progressLng != null) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'progress', 'label': 'YOU'},
        'geometry': {
          'type': 'Point',
          'coordinates': [progressLng, progressLat],
        },
      });
    }

    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_flightPlanReady) {
          final ok = await _ensureGeoJsonSource(c, sourceId, geo);
          if (!ok) return;
          // Dark casing so the route reads on satellite + streets.
          final casing = await _tryAddLayer(
            () => c.addLineLayer(
              sourceId,
              'travel-route-casing',
              const LineLayerProperties(
                lineColor: '#0A1628',
                lineWidth: 8.0,
                lineOpacity: 0.6,
                lineCap: 'round',
                lineJoin: 'round',
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'route',
              ],
            ),
          );
          final line = await _tryAddLayer(
            () => c.addLineLayer(
              sourceId,
              'travel-route-line',
              const LineLayerProperties(
                lineColor: '#4FC3F7',
                lineWidth: 4.0,
                lineOpacity: 1.0,
                lineCap: 'round',
                lineJoin: 'round',
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'route',
              ],
            ),
          );
          // Separate simple layers (no data-driven match) for reliability.
          final origin = await _tryAddLayer(
            () => c.addCircleLayer(
              sourceId,
              'travel-route-origin',
              const CircleLayerProperties(
                circleRadius: 10,
                circleColor: '#43A047',
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2.5,
              ),
              filter: [
                'all',
                [
                  '==',
                  ['get', 'kind'],
                  'waypoint',
                ],
                [
                  '==',
                  ['get', 'role'],
                  'origin',
                ],
              ],
            ),
          );
          final enroute = await _tryAddLayer(
            () => c.addCircleLayer(
              sourceId,
              'travel-route-enroute',
              const CircleLayerProperties(
                circleRadius: 8,
                circleColor: '#4FC3F7',
                circleStrokeColor: '#FFFFFF',
                circleStrokeWidth: 2.25,
              ),
              filter: [
                'all',
                [
                  '==',
                  ['get', 'kind'],
                  'waypoint',
                ],
                [
                  '==',
                  ['get', 'role'],
                  'enroute',
                ],
              ],
            ),
          );
          final dest = await _tryAddLayer(
            () => c.addCircleLayer(
              sourceId,
              'travel-route-dest',
              const CircleLayerProperties(
                circleRadius: 11,
                circleColor: '#FFC107',
                circleStrokeColor: '#0A1628',
                circleStrokeWidth: 2.5,
              ),
              filter: [
                'all',
                [
                  '==',
                  ['get', 'kind'],
                  'waypoint',
                ],
                [
                  '==',
                  ['get', 'role'],
                  'destination',
                ],
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addCircleLayer(
              sourceId,
              'travel-route-progress-halo',
              const CircleLayerProperties(
                circleRadius: 14,
                circleColor: '#FFC107',
                circleOpacity: 0.28,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'progress',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addCircleLayer(
              sourceId,
              'travel-route-progress',
              const CircleLayerProperties(
                circleRadius: 8.5,
                circleColor: '#FFC107',
                circleStrokeColor: '#0A1628',
                circleStrokeWidth: 2.5,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'progress',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              sourceId,
              'travel-route-labels',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 13,
                textColor: '#0A1628',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 2.0,
                textOffset: [0.0, -1.6],
                textFont: ['Noto Sans Regular'],
                textAllowOverlap: true,
              ),
              filter: [
                'in',
                ['get', 'kind'],
                [
                  'literal',
                  ['waypoint', 'progress'],
                ],
              ],
            ),
          );
          if (casing || line || origin || enroute || dest) {
            _flightPlanReady = true;
          }
        } else {
          await c.setGeoJsonSource(sourceId, geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawFlightPlan failed: $e');
        _flightPlanReady = false;
      }
    });
  }

  void resetFlightPlanLayers() {
    _flightPlanReady = false;
  }

  /// Distance rings around the aircraft / trusted fix (km).
  Future<void> drawRangeRings({
    required bool visible,
    double? centerLat,
    double? centerLng,
    List<double> radiiKm = const [5, 10, 20, 40],
  }) async {
    final c = _controller;
    if (c == null) return;

    if (!visible || centerLat == null || centerLng == null) {
      await _clearSourceIfReady(c, 'range-rings', _rangeRingsReady);
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final km in radiiKm) {
      features.add({
        'type': 'Feature',
        'properties': {
          'kind': 'ring',
          'label': km >= 1 ? '${km.round()} km' : '${(km * 1000).round()} m',
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': _circleCoords(centerLat, centerLng, km * 1000),
        },
      });
      // Label at due-east point on the ring.
      final labelPt = _destinationPoint(centerLat, centerLng, km * 1000, 90);
      features.add({
        'type': 'Feature',
        'properties': {
          'kind': 'label',
          'label': km >= 1 ? '${km.round()} km' : '${(km * 1000).round()} m',
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [labelPt.$2, labelPt.$1],
        },
      });
    }

    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_rangeRingsReady) {
          final ok = await _ensureGeoJsonSource(c, 'range-rings', geo);
          if (!ok) return;
          final rings = await _tryAddLayer(
            () => c.addLineLayer(
              'range-rings',
              'range-rings-line',
              const LineLayerProperties(
                lineColor: '#90CAF9',
                lineWidth: 1.4,
                lineOpacity: 0.75,
                lineDasharray: [2.0, 2.0],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'ring',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addSymbolLayer(
              'range-rings',
              'range-rings-labels',
              const SymbolLayerProperties(
                textField: '{label}',
                textSize: 10,
                textColor: '#1565C0',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 1.2,
                textFont: ['Noto Sans Regular'],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'label',
              ],
            ),
          );
          if (rings) _rangeRingsReady = true;
        } else {
          await c.setGeoJsonSource('range-rings', geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawRangeRings failed: $e');
        _rangeRingsReady = false;
      }
    });
  }

  void resetRangeRingLayers() {
    _rangeRingsReady = false;
  }

  /// Truth Mode dual trails: cyan trusted vs amber GPS claim.
  Future<void> drawTruthTrails({
    required bool visible,
    required List<Map<String, double>> trusted,
    required List<Map<String, double>> claimed,
  }) async {
    final c = _controller;
    if (c == null) return;
    const sourceId = 'truth-trails';
    if (!visible || (trusted.length < 2 && claimed.length < 2)) {
      await _clearSourceIfReady(c, sourceId, _truthTrailsReady);
      _truthTrailsReady = false;
      return;
    }

    final features = <Map<String, dynamic>>[];
    if (trusted.length >= 2) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'trusted'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in trusted) [p['longitude'], p['latitude']],
          ],
        },
      });
    }
    if (claimed.length >= 2) {
      features.add({
        'type': 'Feature',
        'properties': {'kind': 'claimed'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in claimed) [p['longitude'], p['latitude']],
          ],
        },
      });
    }
    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_truthTrailsReady) {
          final ok = await _ensureGeoJsonSource(c, sourceId, geo);
          if (!ok) return;
          await _tryAddLayer(
            () => c.addLineLayer(
              sourceId,
              'truth-trusted',
              const LineLayerProperties(
                lineColor: '#4FC3F7',
                lineWidth: 4.0,
                lineOpacity: 0.9,
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'trusted',
              ],
            ),
          );
          await _tryAddLayer(
            () => c.addLineLayer(
              sourceId,
              'truth-claimed',
              const LineLayerProperties(
                lineColor: '#FFC107',
                lineWidth: 3.0,
                lineOpacity: 0.85,
                lineDasharray: [2, 1.5],
              ),
              filter: [
                '==',
                ['get', 'kind'],
                'claimed',
              ],
            ),
          );
          _truthTrailsReady = true;
        } else {
          await c.setGeoJsonSource(sourceId, geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawTruthTrails failed: $e');
        _truthTrailsReady = false;
      }
    });
  }

  /// Spoof heatmap circles (GeoJSON polygons approximated as rings).
  Future<void> drawSpoofHeat({
    required bool visible,
    required List<
            ({
              double lat,
              double lng,
              double radiusM,
              double intensity,
              String label
            })>
        cells,
  }) async {
    final c = _controller;
    if (c == null) return;
    const sourceId = 'spoof-heat';
    if (!visible || cells.isEmpty) {
      await _clearSourceIfReady(c, sourceId, _spoofHeatReady);
      _spoofHeatReady = false;
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final cell in cells) {
      features.add({
        'type': 'Feature',
        'properties': {
          'label': cell.label,
          'intensity': cell.intensity,
        },
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            _circleCoords(cell.lat, cell.lng, cell.radiusM),
          ],
        },
      });
    }
    final geo = {'type': 'FeatureCollection', 'features': features};

    await _withSetupLock(() async {
      try {
        if (!_spoofHeatReady) {
          final ok = await _ensureGeoJsonSource(c, sourceId, geo);
          if (!ok) return;
          await _tryAddLayer(
            () => c.addFillLayer(
              sourceId,
              'spoof-heat-fill',
              const FillLayerProperties(
                fillColor: '#E53935',
                fillOpacity: 0.18,
              ),
            ),
          );
          await _tryAddLayer(
            () => c.addLineLayer(
              sourceId,
              'spoof-heat-outline',
              const LineLayerProperties(
                lineColor: '#E53935',
                lineWidth: 1.5,
                lineOpacity: 0.55,
              ),
            ),
          );
          _spoofHeatReady = true;
        } else {
          await c.setGeoJsonSource(sourceId, geo);
        }
      } catch (e) {
        debugPrint('[OverlayEngine] drawSpoofHeat failed: $e');
        _spoofHeatReady = false;
      }
    });
  }

  /// Approx geodesic circle as closed LineString [lng, lat] ring.
  static List<List<double>> _circleCoords(
    double lat,
    double lng,
    double radiusM, {
    int steps = 64,
  }) {
    final coords = <List<double>>[];
    for (var i = 0; i <= steps; i++) {
      final bearing = (i / steps) * 360.0;
      final p = _destinationPoint(lat, lng, radiusM, bearing);
      coords.add([p.$2, p.$1]);
    }
    return coords;
  }

  /// Destination point given start, distance (m), bearing (deg).
  static (double, double) _destinationPoint(
    double lat,
    double lng,
    double distanceM,
    double bearingDeg,
  ) {
    const r = 6371000.0;
    final brng = bearingDeg * pi / 180;
    final lat1 = lat * pi / 180;
    final lon1 = lng * pi / 180;
    final ang = distanceM / r;
    final lat2 = asin(
      sin(lat1) * cos(ang) + cos(lat1) * sin(ang) * cos(brng),
    );
    final lon2 = lon1 +
        atan2(
          sin(brng) * sin(ang) * cos(lat1),
          cos(ang) - sin(lat1) * sin(lat2),
        );
    return (lat2 * 180 / pi, lon2 * 180 / pi);
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
