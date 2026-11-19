import 'map_basemap_style.dart';

/// Central basemap settings for online raster styles.
///
/// Always used as the bottom layer so the map is never blank. Offline region
/// packs add vector overlays on top when active.
///
/// **Licensing / deps (no API keys required for these public endpoints):**
/// - Street: OSM France — https://www.openstreetmap.fr/
/// - Aviation Dark/Light: CARTO basemaps — https://carto.com/attribution/
/// - Satellite / Hybrid imagery + labels: Esri ArcGIS Online tiles
/// - Terrain: OpenTopoMap — https://opentopomap.org/
class MapBasemapConfig {
  MapBasemapConfig._();

  static const String styleName = 'WHAMI Streets';
  static const String satelliteStyleName = 'WHAMI Satellite';

  /// CDN tile templates (subdomains for parallel fetch).
  /// OSM France raster — no API key, standard XYZ.
  static const List<String> tileUrls = [
    'https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    'https://b.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
    'https://c.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
  ];

  /// Hosts used by [RasterTileCacheService] round-robin fetches (streets).
  static const List<String> cdnHosts = ['a', 'b', 'c'];

  static String tileUrlForHost(String host, int z, int x, int y) =>
      'https://$host.tile.openstreetmap.fr/osmfr/$z/$x/$y.png';

  /// Esri World Imagery (shelf satellite). Path is z/y/x — not XYZ.
  static const String satelliteTileTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/'
      'MapServer/tile/{z}/{y}/{x}';

  static String satelliteTileUrl(int z, int x, int y) =>
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/'
      'MapServer/tile/$z/$y/$x';

  static String esriReferenceTileUrl(int z, int x, int y) =>
      'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/'
      'World_Boundaries_and_Places/MapServer/tile/$z/$y/$x';

  static String cartoDarkTileUrl(String host, int z, int x, int y) =>
      'https://$host.basemaps.cartocdn.com/dark_all/$z/$x/$y.png';

  static String cartoLightTileUrl(String host, int z, int x, int y) =>
      'https://$host.basemaps.cartocdn.com/rastertiles/voyager/$z/$x/$y.png';

  static String openTopoTileUrl(String host, int z, int x, int y) =>
      'https://$host.tile.opentopomap.org/$z/$x/$y.png';

  /// Direct CDN templates when the local raster cache proxy is unavailable.
  static List<String> directTileUrls(MapBasemapStyle style) {
    switch (style) {
      case MapBasemapStyle.aviationDark:
        return [
          for (final h in const ['a', 'b', 'c', 'd'])
            'https://$h.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        ];
      case MapBasemapStyle.aviationLight:
        return [
          for (final h in const ['a', 'b', 'c', 'd'])
            'https://$h.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
        ];
      case MapBasemapStyle.satellite:
      case MapBasemapStyle.hybrid:
        return [satelliteTileTemplate];
      case MapBasemapStyle.terrain:
        return [
          for (final h in const ['a', 'b', 'c'])
            'https://$h.tile.opentopomap.org/{z}/{x}/{y}.png',
        ];
      case MapBasemapStyle.street:
        return tileUrls;
    }
  }

  /// Cache proxy path segment for [RasterTileCacheService].
  static String cacheProviderPath(MapBasemapStyle style) {
    switch (style) {
      case MapBasemapStyle.aviationDark:
        return 'dark';
      case MapBasemapStyle.aviationLight:
        return 'light';
      case MapBasemapStyle.satellite:
        return 'sat';
      case MapBasemapStyle.terrain:
        return 'topo';
      case MapBasemapStyle.street:
        return 'streets';
      case MapBasemapStyle.hybrid:
        return 'sat'; // base; labels layered separately
    }
  }

  static String backgroundColor(MapBasemapStyle style) {
    switch (style) {
      case MapBasemapStyle.aviationDark:
      case MapBasemapStyle.satellite:
      case MapBasemapStyle.hybrid:
        return '#0A1628';
      case MapBasemapStyle.aviationLight:
        return '#E8EEF2';
      case MapBasemapStyle.terrain:
        return '#E4E0D4';
      case MapBasemapStyle.street:
        return '#F2EFE9';
    }
  }

  static String attributionFor(MapBasemapStyle style) {
    switch (style) {
      case MapBasemapStyle.street:
        return attribution;
      case MapBasemapStyle.aviationDark:
      case MapBasemapStyle.aviationLight:
        return '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> '
            '© <a href="https://carto.com/attribution/">CARTO</a>';
      case MapBasemapStyle.satellite:
        return satelliteAttribution;
      case MapBasemapStyle.hybrid:
        return '$satelliteAttribution · Labels © Esri';
      case MapBasemapStyle.terrain:
        return '© <a href="https://opentopomap.org">OpenTopoMap</a> '
            '(CC-BY-SA) · © OpenStreetMap';
    }
  }

  /// HTTP User-Agent required by OSM / community tile operators.
  static const String httpUserAgent =
      'WHAMI/2.0 (verified navigation; https://github.com/rizwanali494/whami_app)';

  /// Shown on the map attribution control.
  static const String attribution =
      '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> '
      '© <a href="https://www.openstreetmap.fr/">OSM France</a>';

  static const String satelliteAttribution =
      'Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics';

  /// Last zoom level with real tiles; MapLibre overscales above this.
  static const double sourceMaxZoom = 19;

  /// Layer visibility ceiling (must stay above typical camera zoom).
  static const double layerMaxZoom = 22;

  static const double tileSize = 256;
}
