import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/data/models/region_pack.dart';
import 'package:WHAMI/data/models/region_metadata.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog includes Victoria/NSW Riverina pack', () async {
    final raw = await rootBundle.loadString('assets/catalog.json');
    final list = jsonDecode(raw) as List<dynamic>;
    final aus = list.cast<Map<String, dynamic>>().firstWhere(
      (e) => e['id'] == 'aus_victoria_nsw',
    );
    expect(aus['name'], contains('Riverina'));
    expect(aus['country'], 'Australia');
    expect(aus['bundled'], isTrue);
    final pack = RegionPack.fromCatalogEntry(aus);
    expect(pack.id, 'aus_victoria_nsw');
    expect(pack.location, 'Australia');
  });

  test('bundled AU pack metadata and files exist on disk', () {
    final dir = Directory('region_packs/aus_victoria_nsw');
    expect(dir.existsSync(), isTrue);
    expect(File('${dir.path}/metadata.json').existsSync(), isTrue);
    expect(File('${dir.path}/landmarks.sqlite').existsSync(), isTrue);
    expect(File('${dir.path}/map.mbtiles').existsSync(), isTrue);

    final meta = RegionMetadata.fromJson(
      jsonDecode(File('${dir.path}/metadata.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(meta.id, 'aus_victoria_nsw');
    expect(meta.bounds.length, 4);
    // Tocumwal area must sit inside pack bounds.
    expect(meta.bounds[0], lessThan(-35.8));
    expect(meta.bounds[2], greaterThan(-35.8));
    expect(meta.bounds[1], lessThan(145.6));
    expect(meta.bounds[3], greaterThan(145.6));
  });
}
