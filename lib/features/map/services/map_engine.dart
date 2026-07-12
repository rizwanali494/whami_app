import 'package:flutter/material.dart';
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
      // identically online and offline, no external dependency. Required
      // for any text-field symbol layer (road/place/POI labels) to render
      // at all — MapLibre silently draws no text without a glyphs source.
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
  Future<void> _clearBaseMapLayers() async {
    final c = _controller;
    if (c == null) return;
    for (final id in _baseMapLayerIds) {
      try {
        await c.removeLayer(id);
      } catch (_) {}
    }
    try {
      await c.removeSource('openmaptiles');
    } catch (_) {}
    try {
      await c.removeSource('open-tiles');
    } catch (_) {}
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
  }) async {
    final c = _controller;
    if (c == null) return;

    await _clearBaseMapLayers();

    final hasLocalTiles =
        localMBTilesUrl != null && localMBTilesUrl.isNotEmpty;

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
    } else {
      // No pack active.
      if (rasterCacheUrl != null && rasterCacheUrl.isNotEmpty) {
        // Raster base tiles routed through RasterTileCacheService: on a
        // cache hit it serves straight from the local SQLite cache (works
        // offline, for any area previously panned over while online); on a
        // miss while online it fetches from CartoDB, caches the tile, and
        // serves it. A single {z}/{x}/{y} template is enough (vs. the 3
        // CartoDB subdomains) since the proxy itself round-robins them.
        await _safeAdd(
          'open-tiles source',
          () => c.addSource(
            'open-tiles',
            RasterSourceProperties(
              tiles: ['$rasterCacheUrl/{z}/{x}/{y}.png'],
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
            maxzoom: 14,
          ),
        );
      } else if (!isOffline) {
        // Cache proxy hasn't finished starting yet — hit CartoDB directly
        // so there's no blank window while it comes up.
        await _safeAdd(
          'open-tiles source',
          () => c.addSource(
            'open-tiles',
            const RasterSourceProperties(
              tiles: [
                'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              ],
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
            maxzoom: 14,
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
