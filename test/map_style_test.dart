import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/config/map_basemap_config.dart';
import 'package:WHAMI/features/map/services/map_engine.dart';

void main() {
  group('TileEngine.generateStyle', () {
    test('embeds light OSM raster when no pack is active', () {
      final style = TileEngine().generateStyle(includeRasterBasemap: true);
      final sources = style['sources'] as Map;
      final layers = style['layers'] as List;

      expect(sources.containsKey('open-tiles'), isTrue);
      final openTiles = sources['open-tiles'] as Map;
      expect(openTiles['type'], 'raster');
      expect(openTiles['maxzoom'], MapBasemapConfig.sourceMaxZoom);
      expect(openTiles['attribution'], contains('OpenStreetMap'));
      expect(openTiles['tiles'], isA<List>());
      expect((openTiles['tiles'] as List).isNotEmpty, isTrue);

      final base = layers.cast<Map>().firstWhere((l) => l['id'] == 'base-tiles');
      expect(base['type'], 'raster');
      expect(base['maxzoom'], MapBasemapConfig.layerMaxZoom);
    });

    test('omits raster when a vector pack will be added imperatively', () {
      final style = TileEngine().generateStyle(includeRasterBasemap: false);
      final sources = style['sources'] as Map;
      expect(sources.containsKey('open-tiles'), isFalse);
      final layers = style['layers'] as List;
      expect(
        layers.cast<Map>().any((l) => l['id'] == 'base-tiles'),
        isFalse,
      );
    });

    test('prefers local raster cache URL when provided', () {
      final style = TileEngine().generateStyle(
        includeRasterBasemap: true,
        rasterCacheUrl: 'http://127.0.0.1:1234',
      );
      final tiles =
          ((style['sources'] as Map)['open-tiles'] as Map)['tiles'] as List;
      expect(tiles.single, 'http://127.0.0.1:1234/{z}/{x}/{y}.png');
    });
  });

  group('MapBasemapConfig', () {
    test('centralizes OSM attribution and zoom ceilings', () {
      expect(MapBasemapConfig.attribution, contains('OpenStreetMap'));
      expect(MapBasemapConfig.sourceMaxZoom, 19);
      expect(MapBasemapConfig.layerMaxZoom, greaterThan(MapBasemapConfig.sourceMaxZoom));
      expect(MapBasemapConfig.tileUrls.length, 3);
      expect(MapBasemapConfig.tileUrls.first, contains('openstreetmap.fr'));
      expect(MapBasemapConfig.tileUrls.first, isNot(contains('cartocdn')));
    });
  });
}
