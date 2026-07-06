/// Generates MapLibre GL style JSON for WHAMI maps.
///
/// When [tileServerBaseUrl] is provided (e.g. 'http://127.0.0.1:52341'),
/// the style uses the local MBTiles tile server and renders a full offline
/// vector map with roads, buildings, water, parks, and POIs from the
/// OpenMapTiles schema.
///
/// When [tileServerBaseUrl] is empty, only the solid background layer is
/// emitted — used when no pack is active.
class OfflineStyle {
  /// Generate MapLibre Style JSON.
  ///
  /// [isOffline]          — true when device has no network.
  /// [tileServerBaseUrl]  — base URL of the local tile server, e.g.
  ///                        'http://127.0.0.1:52341'. Pass empty string
  ///                        when no pack is loaded.
  static Map<String, dynamic> generate({
    required bool isOffline,
    String tileServerBaseUrl = '',
  }) {
    final hasTileServer = tileServerBaseUrl.isNotEmpty;

    // ── Sources ─────────────────────────────────────────────────────────────
    final Map<String, dynamic> sources = {};

    if (hasTileServer) {
      // Local vector source served from the embedded MBTiles HTTP server
      sources['openmaptiles'] = {
        'type': 'vector',
        'tiles': ['$tileServerBaseUrl/{z}/{x}/{y}.pbf'],
        'minzoom': 0,
        'maxzoom': 14,
      };
    } else if (!isOffline) {
      // Online fallback: CartoDB raster (only when online and no local pack)
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

    if (hasTileServer) {
      // ── Vector layers (OpenMapTiles schema) ─────────────────────────────

      // 2. Water bodies (rivers, lakes, sea, canal)
      layers.add({
        'id': 'water',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'water',
        'paint': {
          'fill-color': '#A8D1E7',
          'fill-opacity': 0.9,
        },
      });

      // 3. Waterways (river centre lines, canals, streams)
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

      // 4. Land cover — parks & green areas
      layers.add({
        'id': 'landcover-park',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landcover',
        'filter': [
          '==',
          ['get', 'class'],
          'grass',
        ],
        'paint': {
          'fill-color': '#D4EDBC',
          'fill-opacity': 0.8,
        },
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
        'paint': {
          'fill-color': '#BDDFAD',
          'fill-opacity': 0.75,
        },
      });

      // 5. Landuse — parks, residential, commercial
      layers.add({
        'id': 'landuse-park',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['park', 'pitch', 'recreation_ground', 'garden']],
        ],
        'paint': {
          'fill-color': '#C8E6C0',
          'fill-opacity': 0.85,
        },
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
        'paint': {
          'fill-color': '#EBEBEB',
          'fill-opacity': 0.6,
        },
      });

      layers.add({
        'id': 'landuse-commercial',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'landuse',
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['commercial', 'retail', 'industrial']],
        ],
        'paint': {
          'fill-color': '#F5DEB3',
          'fill-opacity': 0.5,
        },
      });

      // 6. Parks named layer
      layers.add({
        'id': 'park-fill',
        'type': 'fill',
        'source': 'openmaptiles',
        'source-layer': 'park',
        'paint': {
          'fill-color': '#C8E6C0',
          'fill-opacity': 0.7,
        },
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

      // 8. Roads — casing (outline) first, then fill on top
      // Motorway casing
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

      // Trunk casing
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

      // Primary casing
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
          'line-color': '#BBB',
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

      // Secondary/Tertiary casing
      layers.add({
        'id': 'road-secondary-casing',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['secondary', 'tertiary']],
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

      // Motorway fill
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

      // Trunk fill
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

      // Primary fill
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

      // Secondary fill
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

      // Tertiary fill
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

      // Minor roads (residential, service, track)
      layers.add({
        'id': 'road-minor',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['minor', 'service', 'track']],
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

      // Paths and footways
      layers.add({
        'id': 'road-path',
        'type': 'line',
        'source': 'openmaptiles',
        'source-layer': 'transportation',
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['path', 'pedestrian', 'cycleway']],
        ],
        'minzoom': 13,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': '#C8B89A',
          'line-width': 1.0,
          'line-dasharray': [2, 2],
        },
      });

      // 9. Boundary lines (admin borders)
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

      // 10. POI labels (symbols — will show when glyphs are bundled)
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
          'icon-image': 'marker',
          'icon-size': 0.8,
        },
        'paint': {
          'text-color': '#333333',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 1.5,
        },
      });

      // 11. Road / street name labels
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

      // 12. Water name labels (rivers, lakes)
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

      // 14. Park / green area name labels
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

      // 15. Place labels: suburb / neighbourhood
      layers.add({
        'id': 'place-suburb',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 11,
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['suburb', 'neighbourhood', 'quarter']],
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

      // 16. Place labels: village / town
      layers.add({
        'id': 'place-town',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 8,
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['village', 'town']],
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

      // 17. Place labels: city
      layers.add({
        'id': 'place-city',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 4,
        'filter': [
          'in',
          ['get', 'class'],
          ['literal', ['city', 'capital']],
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
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'],
        },
        'paint': {
          'text-color': '#1A1A1A',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      });
    } else if (!isOffline) {
      // Online CartoDB raster layer (no local pack available)
      layers.add({
        'id': 'base-tiles',
        'type': 'raster',
        'source': 'open-tiles',
        'minzoom': 0,
        'maxzoom': 14,
      });
    }

    return {
      'version': 8,
      'name': 'WHAMI Offline',
      'sources': sources,
      'layers': layers,
    };
  }
}
