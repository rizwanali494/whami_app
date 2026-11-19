import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/models/region_pack.dart';

void main() {
  test('bundled AU catalog entry is demo without offline tiles', () {
    final pack = RegionPack.fromCatalogEntry({
      'id': 'aus_victoria_nsw',
      'name': 'Victoria / NSW Riverina',
      'country': 'Australia',
      'packType': 'Aviation',
      'bundled': true,
      'downloadUrl': null,
      'checksum': 'bundled-demo',
      'sizeBytes': 32768,
      'trustScore': 85,
    });
    expect(pack.isDemoPack, isTrue);
    expect(pack.hasOfflineMapTiles, isFalse);
    expect(pack.size, 'Demo');
    expect(pack.includedData, contains('Landmarks'));
    expect(pack.coverageSummary, contains('basemap'));
  });

  test('full urban pack advertises offline tiles', () {
    final pack = RegionPack.fromCatalogEntry({
      'id': 'usa_san_francisco',
      'name': 'San Francisco',
      'country': 'United States',
      'packType': 'Urban',
      'bundled': false,
      'sizeBytes': 31172601,
      'checksum': 'abc',
      'trustScore': 90,
    });
    expect(pack.isDemoPack, isFalse);
    expect(pack.hasOfflineMapTiles, isTrue);
  });
}
