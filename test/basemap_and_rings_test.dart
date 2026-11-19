import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/config/map_basemap_config.dart';
import 'package:WHAMI/features/map/services/map_engine.dart';

void main() {
  test('satellite style embeds Esri-backed cache path', () {
    final style = TileEngine().generateStyle(
      rasterCacheUrl: 'http://127.0.0.1:9999',
      satellite: true,
    );
    final tiles = style['sources']['open-tiles']['tiles'] as List;
    expect(tiles.single, contains('/sat/{z}/{x}/{y}.png'));
    expect(style['name'], MapBasemapConfig.satelliteStyleName);
    expect(
      style['sources']['open-tiles']['attribution'],
      contains('Esri'),
    );
  });

  test('streets style uses default cache path', () {
    final style = TileEngine().generateStyle(
      rasterCacheUrl: 'http://127.0.0.1:9999',
      satellite: false,
    );
    final tiles = style['sources']['open-tiles']['tiles'] as List;
    expect(tiles.single, 'http://127.0.0.1:9999/{z}/{x}/{y}.png');
    expect(jsonEncode(style), isNot(contains('/sat/')));
  });

  test('Esri satellite template uses z/y/x order', () {
    expect(MapBasemapConfig.satelliteTileTemplate, contains('{z}/{y}/{x}'));
    expect(MapBasemapConfig.satelliteTileUrl(5, 10, 20), endsWith('/5/20/10'));
  });
}
