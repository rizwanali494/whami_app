import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/landmark.dart';

class LandmarkDatabase {
  Database? _db;
  String? _currentPath;

  bool get isOpen => _db != null;

  /// Open SQLite database connection
  Future<void> open(String dbPath) async {
    if (_db != null) {
      if (_currentPath == dbPath) return; // Already open
      await close();
    }

    _currentPath = dbPath;
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        // Ensure tables exist in case a database file was created empty
        await _createTables(db);
      },
    );
    debugPrint('[LandmarkDatabase] Opened SQLite DB at: $dbPath');
  }

  /// Create main table and spatial indices
  Future<void> _createTables(Database db) async {
    // 1. Main landmarks table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS landmarks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        description TEXT,
        verified INTEGER DEFAULT 0,
        confidence REAL DEFAULT 1.0,
        imagePath TEXT,
        source TEXT NOT NULL, -- 'SYSTEM', 'USER', 'AR'
        isFavorite INTEGER DEFAULT 0,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      );
    ''');

    // 2. Index on category to speed up filters
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_landmarks_category ON landmarks (category);'
    );

    // 3. RTree spatial lookup table (minLat, maxLat, minLng, maxLng)
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS landmark_index USING rtree(
          id,              -- matches landmarks.rowid
          minLat, maxLat,  
          minLng, maxLng   
        );
      ''');

      // 4. Triggers to automatically sync RTree index with primary table
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS landmark_insert_rtree
        AFTER INSERT ON landmarks
        BEGIN
          INSERT OR REPLACE INTO landmark_index (id, minLat, maxLat, minLng, maxLng)
          VALUES (new.rowid, new.latitude, new.latitude, new.longitude, new.longitude);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS landmark_update_rtree
        AFTER UPDATE ON landmarks
        BEGIN
          INSERT OR REPLACE INTO landmark_index (id, minLat, maxLat, minLng, maxLng)
          VALUES (new.rowid, new.latitude, new.latitude, new.longitude, new.longitude);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS landmark_delete_rtree
        AFTER DELETE ON landmarks
        BEGIN
          DELETE FROM landmark_index WHERE id = old.rowid;
        END;
      ''');

      // Backfill RTree index if data already exists in landmarks table but rtree is empty
      final rtreeCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM landmark_index;')
      ) ?? 0;
      final landmarksCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM landmarks;')
      ) ?? 0;

      if (rtreeCount == 0 && landmarksCount > 0) {
        await db.execute('''
          INSERT INTO landmark_index (id, minLat, maxLat, minLng, maxLng)
          SELECT rowid, latitude, latitude, longitude, longitude FROM landmarks;
        ''');
        debugPrint('[LandmarkDatabase] Backfilled RTree spatial index with $landmarksCount points.');
      }

    } catch (e) {
      debugPrint('[LandmarkDatabase] SQLite RTree extension not available. Falling back to normal indexing: $e');
      // Fallback index for standard lat/lng searches
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_landmarks_coords ON landmarks (latitude, longitude);'
      );
    }
  }

  /// Close SQLite database connection
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      debugPrint('[LandmarkDatabase] Closed SQLite DB at: $_currentPath');
      _currentPath = null;
    }
  }

  /// Insert a single landmark
  Future<int> insertLandmark(Landmark landmark) async {
    final db = _db;
    if (db == null) throw StateError('Database not open');
    return await db.insert(
      'landmarks',
      landmark.toSqlRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update a landmark
  Future<int> updateLandmark(Landmark landmark) async {
    final db = _db;
    if (db == null) throw StateError('Database not open');
    return await db.update(
      'landmarks',
      landmark.toSqlRow(),
      where: 'id = ?',
      whereArgs: [landmark.id],
    );
  }

  /// Delete a landmark by ID
  Future<int> deleteLandmark(String id) async {
    final db = _db;
    if (db == null) throw StateError('Database not open');
    return await db.delete(
      'landmarks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Fetch in bounding box using RTree (with standard fallback)
  Future<List<Landmark>> getInBounds(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng, {
    int limit = 500,
  }) async {
    final db = _db;
    if (db == null) return [];

    try {
      // Check if virtual table exists and is active
      final hasRTree = await _hasRTreeTable(db);
      if (hasRTree) {
        // Query using fast RTree index join
        final results = await db.rawQuery('''
          SELECT l.* FROM landmarks l
          JOIN landmark_index idx ON l.rowid = idx.id
          WHERE idx.minLat >= ? AND idx.maxLat <= ?
            AND idx.minLng >= ? AND idx.maxLng <= ?
          LIMIT ?;
        ''', [minLat, maxLat, minLng, maxLng, limit]);

        return results.map((row) => Landmark.fromSqlRow(row)).toList();
      }
    } catch (e) {
      debugPrint('[LandmarkDatabase] RTree query failed, falling back: $e');
    }

    // Fallback standard bounding box query
    final results = await db.query(
      'landmarks',
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [minLat, maxLat, minLng, maxLng],
      limit: limit,
    );
    return results.map((row) => Landmark.fromSqlRow(row)).toList();
  }

  /// Check if the RTree index exists
  Future<bool> _hasRTreeTable(Database db) async {
    try {
      final res = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='landmark_index';"
      );
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Query nearby landmarks using rough bounding box + distance filter
  Future<List<Landmark>> getNearby(
    double lat,
    double lng,
    double radiusMeters, {
    int limit = 100,
  }) async {
    // 1 degree latitude is approx 111,000 meters.
    final latDelta = radiusMeters / 111000.0;
    // 1 degree longitude is approx 111,000 * cos(lat) meters.
    final lngDelta = radiusMeters / (111000.0 * 0.8); // rough average cos(lat)

    final minLat = lat - latDelta;
    final maxLat = lat + latDelta;
    final minLng = lng - lngDelta;
    final maxLng = lng + lngDelta;

    final inBox = await getInBounds(minLat, minLng, maxLat, maxLng, limit: limit * 2);

    // Sort by actual haversine distance
    inBox.sort((a, b) {
      final d1 = _haversine(lat, lng, a.latitude, a.longitude);
      final d2 = _haversine(lat, lng, b.latitude, b.longitude);
      return d1.compareTo(d2);
    });

    return inBox.take(limit).toList();
  }

  /// Proximity utility
  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    // Earth radius in meters
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLon = (lon2 - lon1) * 3.141592653589793 / 180;
    // Simple fast distance approximation for sorting
    return r * (dLat * dLat + dLon * dLon);
  }

  /// Get by category
  Future<List<Landmark>> getByCategory(String category, {int limit = 100}) async {
    final db = _db;
    if (db == null) return [];
    final results = await db.query(
      'landmarks',
      where: 'category = ?',
      whereArgs: [category],
      limit: limit,
    );
    return results.map((row) => Landmark.fromSqlRow(row)).toList();
  }

  /// Search by text
  Future<List<Landmark>> search(String query, {int limit = 50}) async {
    final db = _db;
    if (db == null) return [];
    final results = await db.query(
      'landmarks',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      limit: limit,
    );
    return results.map((row) => Landmark.fromSqlRow(row)).toList();
  }

  /// Lookup single landmark
  Future<Landmark?> getById(String id) async {
    final db = _db;
    if (db == null) return null;
    final results = await db.query(
      'landmarks',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return Landmark.fromSqlRow(results.first);
  }
}
