import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Caches CartoDB raster basemap tiles locally as they're fetched while
/// online, and fronts them behind a local HTTP server shaped like the CDN
/// itself (`/{z}/{x}/{y}.png`).
///
/// A request is served from the local SQLite cache when present; on a miss
/// while online it's fetched from CartoDB, stored, and served. This means
/// any area a user has panned over once while online stays visible later
/// when offline with no region pack active, instead of falling back to a
/// blank background.
class RasterTileCacheService {
  static const _cdnHosts = ['a', 'b', 'c'];

  // Roughly bounds cache disk usage — 256px PNG/JPEG tiles from this CDN
  // run a few KB to ~30KB each, so this caps around a couple hundred MB.
  static const _maxCachedTiles = 4000;

  HttpServer? _server;
  Database? _db;
  int _hostIndex = 0;

  String get baseUrl =>
      _server != null ? 'http://127.0.0.1:${_server!.port}' : '';

  Future<void> start() async {
    if (_server != null) return;

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}/WHAMI');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      _db = await openDatabase(
        '${dir.path}/raster_tile_cache.sqlite',
        version: 1,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE tiles ('
          'zoom_level INTEGER NOT NULL, '
          'tile_column INTEGER NOT NULL, '
          'tile_row INTEGER NOT NULL, '
          'tile_data BLOB NOT NULL, '
          'accessed_at INTEGER NOT NULL, '
          'PRIMARY KEY (zoom_level, tile_column, tile_row))',
        ),
      );

      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[RasterTileCacheService] Running on $baseUrl');

      _server!.listen((HttpRequest request) async {
        try {
          await _handleRequest(request);
        } catch (e) {
          debugPrint('[RasterTileCacheService] Error handling request: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('[RasterTileCacheService] Failed to start: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    final parts = request.uri.path.split('/');

    if (parts.length < 4 || _db == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final z = int.tryParse(parts[1]);
    final x = int.tryParse(parts[2]);
    final y = int.tryParse(parts[3].split('.').first);

    if (z == null || x == null || y == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final tile = await _readTile(z, x, y) ?? await _fetchAndStore(z, x, y);

    if (tile == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    response.headers.contentType = ContentType('image', 'png');
    response.headers.set('Cache-Control', 'max-age=3600');
    response.add(tile);
    await response.close();
  }

  Future<List<int>?> _readTile(int z, int x, int y) async {
    final db = _db;
    if (db == null) return null;

    try {
      final rows = await db.rawQuery(
        'SELECT tile_data FROM tiles '
        'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, y],
      );
      if (rows.isEmpty) return null;

      unawaited(
        db.rawUpdate(
          'UPDATE tiles SET accessed_at = ? '
          'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
          [DateTime.now().millisecondsSinceEpoch, z, x, y],
        ),
      );

      return rows.first['tile_data'] as List<int>?;
    } catch (e) {
      debugPrint('[RasterTileCacheService] Read failed for $z/$x/$y: $e');
      return null;
    }
  }

  Future<List<int>?> _fetchAndStore(int z, int x, int y) async {
    final host = _cdnHosts[_hostIndex++ % _cdnHosts.length];
    final url = Uri.parse(
      'https://$host.basemaps.cartocdn.com/light_all/$z/$x/$y.png',
    );

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      unawaited(_storeTile(z, x, y, res.bodyBytes));
      return res.bodyBytes;
    } catch (e) {
      debugPrint('[RasterTileCacheService] Fetch failed for $z/$x/$y: $e');
      return null;
    }
  }

  Future<void> _storeTile(int z, int x, int y, List<int> data) async {
    final db = _db;
    if (db == null) return;

    try {
      await db.insert('tiles', {
        'zoom_level': z,
        'tile_column': x,
        'tile_row': y,
        'tile_data': data,
        'accessed_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _evictLeastRecentlyUsed(db);
    } catch (e) {
      debugPrint('[RasterTileCacheService] Store failed for $z/$x/$y: $e');
    }
  }

  Future<void> _evictLeastRecentlyUsed(Database db) async {
    final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM tiles');
    final count = Sqflite.firstIntValue(countRows) ?? 0;
    if (count <= _maxCachedTiles) return;

    await db.rawDelete(
      'DELETE FROM tiles WHERE rowid IN '
      '(SELECT rowid FROM tiles ORDER BY accessed_at ASC LIMIT ?)',
      [count - _maxCachedTiles],
    );
  }

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
    debugPrint('[RasterTileCacheService] Server stopped');
  }
}
