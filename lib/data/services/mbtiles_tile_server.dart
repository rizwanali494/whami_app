import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// A lightweight local HTTP tile server that serves map tiles from SQLite MBTiles files.
class MBTilesTileServer {
  HttpServer? _server;
  Database? _db;

  /// Get the base URL of the local server
  String get baseUrl =>
      _server != null ? 'http://127.0.0.1:${_server!.port}' : '';

  /// Start the local HTTP server on a random free port
  Future<void> start() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[MBTilesTileServer] Running on $baseUrl');

      _server!.listen((HttpRequest request) async {
        try {
          await _handleRequest(request);
        } catch (e) {
          debugPrint('[MBTilesTileServer] Error handling request: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[MBTilesTileServer] Failed to start server: $e');
    }
  }

  /// Change the active MBTiles file path
  Future<void> setActiveMBTiles(String? path) async {
    if (_db != null) {
      try {
        await _db!.close();
      } catch (_) {}
      _db = null;
    }

    if (path != null && path.isNotEmpty) {
      try {
        _db = await openDatabase(path, readOnly: true);
        debugPrint('[MBTilesTileServer] Connected to MBTiles DB at: $path');
      } catch (e) {
        debugPrint('[MBTilesTileServer] Failed to open MBTiles database: $e');
      }
    }
  }

  /// Handles incoming HTTP requests for tiles
  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;

    // Expected path format: /<z>/<x>/<y>.png (or similar raster formats)
    final parts = path.split('/');
    if (parts.length < 4) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final zStr = parts[1];
    final xStr = parts[2];
    final yStr = parts[3].split('.').first;

    final z = int.tryParse(zStr);
    final x = int.tryParse(xStr);
    final yXYZ = int.tryParse(yStr);

    if (z == null || x == null || yXYZ == null || _db == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    // Convert XYZ (Mapbox/MapLibre GL format) to TMS (MBTiles format) y-coordinate
    final yTMS = (1 << z) - 1 - yXYZ;

    try {
      // Try TMS first
      List<Map<String, Object?>> results = await _db!.rawQuery(
        'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, yTMS],
      );

      // Fallback to XYZ if TMS yields no result
      if (results.isEmpty) {
        results = await _db!.rawQuery(
          'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
          [z, x, yXYZ],
        );
      }

      if (results.isNotEmpty) {
        final tileData = results.first['tile_data'] as List<int>?;
        if (tileData != null && tileData.isNotEmpty) {
          // Detect format from header bytes
          String mime = 'image/png'; // default
          List<int> bodyBytes = tileData;
          if (tileData.length > 2) {
            if (tileData[0] == 0xFF && tileData[1] == 0xD8) {
              mime = 'image/jpeg';
            } else if (tileData[0] == 0x1F && tileData[1] == 0x8B) {
              // gzip compressed vector tile (mvt/pbf). Decompress here
              // rather than setting Content-Encoding: gzip and relying on
              // the HTTP client to auto-decompress — MapLibre Native's tile
              // fetcher does not reliably honor that header, and would
              // otherwise try to parse raw gzip bytes as protobuf, which
              // fails silently per-tile (no error, tile just never renders).
              mime = 'application/x-protobuf';
              bodyBytes = gzip.decode(tileData);
            } else if (tileData[0] == 0x52 &&
                tileData[1] == 0x49 &&
                tileData[2] == 0x46 &&
                tileData[3] == 0x46) {
              // RIFF -> WebP
              mime = 'image/webp';
            }
          }

          response.headers.contentType = ContentType.parse(mime);
          response.headers.set('Cache-Control', 'max-age=3600');
          // Add CORS just in case MapLibre checks it internally on some platforms
          response.headers.set('Access-Control-Allow-Origin', '*');
          response.add(bodyBytes);
          await response.close();
          debugPrint(
            '[MBTilesTileServer] Served $path as $mime (${bodyBytes.length} bytes, '
            'source ${tileData.length} bytes)',
          );
          return;
        }
      } else {
        debugPrint(
          '[MBTilesTileServer] 404 Not Found in DB: $path (z=$z, x=$x, yTMS=$yTMS, yXYZ=$yXYZ)',
        );
      }
    } catch (e) {
      debugPrint('[MBTilesTileServer] Query failed for $path: $e');
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  /// Shut down the server and database connections
  Future<void> stop() async {
    if (_db != null) {
      try {
        await _db!.close();
      } catch (_) {}
      _db = null;
    }
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {}
      _server = null;
    }
    debugPrint('[MBTilesTileServer] Server stopped');
  }
}
