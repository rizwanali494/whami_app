/// Central basemap settings for the light OSM-derived raster layer.
///
/// Used when no offline region pack is active. Tile data is OSM cartography
/// served via CARTO's light style (not the raw openstreetmap.org tile CDN).
class MapBasemapConfig {
  MapBasemapConfig._();

  static const String styleName = 'WHAMI Light OSM';

  /// CDN tile templates (subdomains for parallel fetch).
  static const List<String> tileUrls = [
    'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    'https://b.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
    'https://c.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
  ];

  /// Hosts used by [RasterTileCacheService] round-robin fetches.
  static const List<String> cdnHosts = ['a', 'b', 'c'];

  static String tileUrlForHost(String host, int z, int x, int y) =>
      'https://$host.basemaps.cartocdn.com/light_all/$z/$x/$y.png';

  /// Shown on the map attribution control.
  static const String attribution =
      '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> '
      '© <a href="https://carto.com/attributions">CARTO</a>';

  /// Last zoom level with real tiles; MapLibre overscales above this.
  static const double sourceMaxZoom = 18;

  /// Layer visibility ceiling (must stay above typical camera zoom).
  static const double layerMaxZoom = 22;

  static const double tileSize = 256;
}
