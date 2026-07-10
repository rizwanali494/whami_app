import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'mbtiles_tile_server.dart';

/// The always-available bundled world overview (country outlines,
/// coastlines, ~250 major cities, zoom 0-6, built from Natural Earth
/// 1:110m data). Shown when no region pack is active and there's no
/// internet for the raster fallback, so the map is never completely
/// blank — served locally, so it needs no network of its own either.
class WorldBasemapService {
  final MBTilesTileServer tileServer = MBTilesTileServer();

  Future<void> start() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final outFile = File('${docsDir.path}/WHAMI/world_basemap.mbtiles');
      if (!await outFile.parent.exists()) {
        await outFile.parent.create(recursive: true);
      }

      final byteData = await rootBundle.load(
        'assets/world_basemap/world.mbtiles',
      );
      await outFile.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );

      await tileServer.start();
      await tileServer.setActiveMBTiles(outFile.path);
      debugPrint('[WorldBasemapService] Ready at ${outFile.path}');
    } catch (e) {
      debugPrint('[WorldBasemapService] Failed to start: $e');
    }
  }

  String get baseUrl => tileServer.baseUrl;
}
