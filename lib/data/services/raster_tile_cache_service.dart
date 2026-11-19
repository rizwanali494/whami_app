import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/config/map_basemap_config.dart';

/// Caches online street-map raster tiles behind a local HTTP server
/// shaped like the CDN (`/{z}/{x}/{y}.png`).
///
/// Cache hits are served immediately. Misses coalesce duplicate in-flight
/// requests, fetch over a keep-alive [HttpClient], store for seven days, and
/// only evict when the store exceeds 110% of capacity.
class RasterTileCacheService {
  static const _maxCachedTiles = 4000;
  static const _evictThreshold = 4400; // 110% — avoid thrashing every insert
  static const _ttl = Duration(days: 7);
  /// Bumped when CDN provider set changes (styles / hybrid labels).
  static const _dbVersion = 5;

  HttpServer? _server;
  Database? _db;
  HttpClient? _httpClient;
  int _hostIndex = 0;

  /// In-flight CDN fetches keyed by `z/x/y` so parallel map requests share one.
  final Map<String, Future<List<int>?>> _inflight = {};

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

      _httpClient = HttpClient()
        ..userAgent = MapBasemapConfig.httpUserAgent
        ..idleTimeout = const Duration(seconds: 60)
        ..maxConnectionsPerHost = 4
        ..connectionTimeout = const Duration(seconds: 20);

      _db = await openDatabase(
        '${dir.path}/raster_tile_cache.sqlite',
        version: _dbVersion,
        onCreate: (db, _) => _createSchema(db),
        onUpgrade: (db, oldVersion, newVersion) async {
          // Provider switch (e.g. CARTO watermark → OSM FR): wipe stale tiles.
          await db.execute('DROP TABLE IF EXISTS tiles');
          await _createSchema(db);
        },
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

  Future<void> _createSchema(Database db) async {
    await db.execute(
      'CREATE TABLE tiles ('
      'provider TEXT NOT NULL DEFAULT \'streets\', '
      'zoom_level INTEGER NOT NULL, '
      'tile_column INTEGER NOT NULL, '
      'tile_row INTEGER NOT NULL, '
      'tile_data BLOB NOT NULL, '
      'accessed_at INTEGER NOT NULL, '
      'fetched_at INTEGER NOT NULL, '
      'PRIMARY KEY (provider, zoom_level, tile_column, tile_row))',
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    final parts = request.uri.path.split('/').where((p) => p.isNotEmpty).toList();

    // /{z}/{x}/{y}.png  or  /{provider}/{z}/{x}/{y}.png
    const known = {'streets', 'sat', 'dark', 'light', 'topo', 'labels'};
    String provider = 'streets';
    List<String> coords = parts;
    if (parts.isNotEmpty && known.contains(parts.first)) {
      provider = parts.first;
      coords = parts.skip(1).toList();
    }

    if (coords.length < 3 || _db == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final z = int.tryParse(coords[0]);
    final x = int.tryParse(coords[1]);
    final y = int.tryParse(coords[2].split('.').first);

    if (z == null || x == null || y == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final tile = await _readTile(provider, z, x, y) ??
        await _fetchAndStore(provider, z, x, y);

    if (tile == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    response.headers.contentType = ContentType('image', 'png');
    response.headers.set('Cache-Control', 'max-age=604800');
    response.add(tile);
    await response.close();
  }

  Future<List<int>?> _readTile(String provider, int z, int x, int y) async {
    final db = _db;
    if (db == null) return null;

    try {
      final rows = await db.rawQuery(
        'SELECT tile_data, fetched_at FROM tiles '
        'WHERE provider = ? AND zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [provider, z, x, y],
      );
      if (rows.isEmpty) return null;

      final fetchedAt = rows.first['fetched_at'] as int? ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
      if (fetchedAt > 0 && age > _ttl.inMilliseconds) {
        // Stale — treat as miss so we refresh from CDN.
        return null;
      }

      unawaited(
        db.rawUpdate(
          'UPDATE tiles SET accessed_at = ? '
          'WHERE provider = ? AND zoom_level = ? AND tile_column = ? AND tile_row = ?',
          [DateTime.now().millisecondsSinceEpoch, provider, z, x, y],
        ),
      );

      return rows.first['tile_data'] as List<int>?;
    } catch (e) {
      debugPrint('[RasterTileCacheService] Read failed for $provider/$z/$x/$y: $e');
      return null;
    }
  }

  Future<List<int>?> _fetchAndStore(String provider, int z, int x, int y) {
    final key = '$provider/$z/$x/$y';
    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _doFetchAndStore(provider, z, x, y).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  Future<List<int>?> _doFetchAndStore(
    String provider,
    int z,
    int x,
    int y,
  ) async {
    final client = _httpClient;
    if (client == null) return null;

    final host = MapBasemapConfig
        .cdnHosts[_hostIndex++ % MapBasemapConfig.cdnHosts.length];
    final Uri url;
    switch (provider) {
      case 'sat':
        url = Uri.parse(MapBasemapConfig.satelliteTileUrl(z, x, y));
      case 'labels':
        url = Uri.parse(MapBasemapConfig.esriReferenceTileUrl(z, x, y));
      case 'dark':
        url = Uri.parse(MapBasemapConfig.cartoDarkTileUrl(host, z, x, y));
      case 'light':
        url = Uri.parse(MapBasemapConfig.cartoLightTileUrl(host, z, x, y));
      case 'topo':
        url = Uri.parse(MapBasemapConfig.openTopoTileUrl(host, z, x, y));
      case 'streets':
      default:
        url = Uri.parse(MapBasemapConfig.tileUrlForHost(host, z, x, y));
    }

    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, MapBasemapConfig.httpUserAgent);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;

      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;

      unawaited(_storeTile(provider, z, x, y, bytes));
      return bytes;
    } catch (e) {
      debugPrint(
        '[RasterTileCacheService] Fetch failed for $provider/$z/$x/$y: $e',
      );
      return null;
    }
  }

  Future<void> _storeTile(
    String provider,
    int z,
    int x,
    int y,
    List<int> data,
  ) async {
    final db = _db;
    if (db == null) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('tiles', {
        'provider': provider,
        'zoom_level': z,
        'tile_column': x,
        'tile_row': y,
        'tile_data': data,
        'accessed_at': now,
        'fetched_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _evictLeastRecentlyUsed(db);
    } catch (e) {
      debugPrint(
        '[RasterTileCacheService] Store failed for $provider/$z/$x/$y: $e',
      );
    }
  }

  Future<void> _evictLeastRecentlyUsed(Database db) async {
    final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM tiles');
    final count = Sqflite.firstIntValue(countRows) ?? 0;
    // Only evict when well over capacity to avoid thrashing every insert.
    if (count <= _evictThreshold) return;

    await db.rawDelete(
      'DELETE FROM tiles WHERE rowid IN '
      '(SELECT rowid FROM tiles ORDER BY accessed_at ASC LIMIT ?)',
      [count - _maxCachedTiles],
    );
  }

  Future<void> stop() async {
    _inflight.clear();
    _httpClient?.close(force: true);
    _httpClient = null;
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
