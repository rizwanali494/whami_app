/// Central basemap settings for the default online street map.
///
/// Used always as the bottom layer so the map is never blank. Offline region
/// packs add vector overlays on top when active.
///
/// CARTO free basemaps now require an API key (they return watermark tiles),
/// so we use OpenStreetMap France raster tiles — no key, standard XYZ.
class MapBasemapConfig {
  MapBasemapConfig._();

  static const String styleName = 'WHAMI Streets';

  /// CDN tile templates (subdomains for parallel fetch).
  static const List<String> tileUrls = [
    'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    'https://b.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    'https://c.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
  ];

  /// Hosts used by [RasterTileCacheService] round-robin fetches.
  static const List<String> cdnHosts = ['a', 'b', 'c'];

  static String tileUrlForHost(String host, int z, int x, int y) =>
      'https://$host.tile.openstreetmap.fr/osmfr/$z/$x/$y.png';

  /// HTTP User-Agent required by OSM tile operators.
  static const String httpUserAgent =
      'WHAMI/2.0 (verified navigation; https://github.com/rizwanali494/whami_app)';

  /// Shown on the map attribution control.
  static const String attribution =
      '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> '
      '© <a href="https://www.openstreetmap.fr/">OSM France</a>';

  /// Last zoom level with real tiles; MapLibre overscales above this.
  static const double sourceMaxZoom = 19;

  /// Layer visibility ceiling (must stay above typical camera zoom).
  static const double layerMaxZoom = 22;

  static const double tileSize = 256;
}
