import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/landmark.dart';
import 'landmark_database.dart';
import 'region_engine.dart';

class LandmarkEngine {
  final RegionEngine regionEngine;
  final LandmarkDatabase db;

  // In-memory cache for visible viewport queries
  double? _cachedMinLat;
  double? _cachedMinLng;
  double? _cachedMaxLat;
  double? _cachedMaxLng;
  List<Landmark> _cachedLandmarks = [];

  LandmarkEngine({
    required this.regionEngine,
    required this.db,
  });

  /// In-memory cache invalidation
  void invalidateCache() {
    _cachedMinLat = null;
    _cachedMinLng = null;
    _cachedMaxLat = null;
    _cachedMaxLng = null;
    _cachedLandmarks.clear();
    debugPrint('[LandmarkEngine] In-memory cache invalidated.');
  }

  /// Check if the query bounding box is completely enclosed inside the cached bounding box.
  bool _isEnclosed(double minLat, double minLng, double maxLat, double maxLng) {
    if (_cachedMinLat == null || _cachedMinLng == null || _cachedMaxLat == null || _cachedMaxLng == null) {
      return false;
    }
    // Check if query is fully within cached boundaries
    return minLat >= _cachedMinLat! &&
           maxLat <= _cachedMaxLat! &&
           minLng >= _cachedMinLng! &&
           maxLng <= _cachedMaxLng!;
  }

  /// Query visible landmarks with cache hits
  Future<List<Landmark>> getVisibleLandmarks(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng, {
    int limit = 500,
  }) async {
    if (!db.isOpen) return [];

    // Cache hit check
    if (_isEnclosed(minLat, minLng, maxLat, maxLng)) {
      // debugPrint('[LandmarkEngine] Visible bounds cache HIT!');
      return _cachedLandmarks.where((l) {
        return l.latitude >= minLat &&
               l.latitude <= maxLat &&
               l.longitude >= minLng &&
               l.longitude <= maxLng;
      }).take(limit).toList();
    }

    // Cache miss: Query database and buffer a slightly wider window (e.g. 50% larger viewport)
    // to absorb subsequent small panning adjustments without querying SQLite.
    // debugPrint('[LandmarkEngine] Visible bounds cache MISS. Fetching SQLite...');
    final latBuffer = (maxLat - minLat) * 0.5;
    final lngBuffer = (_maxMax(maxLng - minLng) * 0.5);

    final bufferMinLat = minLat - latBuffer;
    final bufferMaxLat = maxLat + latBuffer;
    final bufferMinLng = minLng - lngBuffer;
    final bufferMaxLng = maxLng + lngBuffer;

    final results = await db.getInBounds(
      bufferMinLat,
      bufferMinLng,
      bufferMaxLat,
      bufferMaxLng,
      limit: limit * 2,
    );

    // Save cache
    _cachedMinLat = bufferMinLat;
    _cachedMinLng = bufferMinLng;
    _cachedMaxLat = bufferMaxLat;
    _cachedMaxLng = bufferMaxLng;
    _cachedLandmarks = results;

    // Return filtered viewport results
    return results.where((l) {
      return l.latitude >= minLat &&
             l.latitude <= maxLat &&
             l.longitude >= minLng &&
             l.longitude <= maxLng;
    }).take(limit).toList();
  }

  double _maxMax(double val) => val.abs() < 0.001 ? 0.01 : val.abs();

  /// Query nearby sorted by distance
  Future<List<Landmark>> getNearbyLandmarks(
    double lat,
    double lng,
    double radiusMeters, {
    int limit = 100,
  }) async {
    if (!db.isOpen) return [];
    return await db.getNearby(lat, lng, radiusMeters, limit: limit);
  }

  /// Text-based search
  Future<List<Landmark>> searchLandmarks(String query, {int limit = 50}) async {
    if (!db.isOpen) return [];
    return await db.search(query, limit: limit);
  }

  /// Fetch closest landmark (useful for position anchoring & cameras)
  Future<Landmark?> matchNearestLandmark(
    double lat,
    double lng, {
    double maxDistanceMeters = 5000.0,
  }) async {
    if (!db.isOpen) return null;

    final nearby = await db.getNearby(lat, lng, maxDistanceMeters, limit: 1);
    if (nearby.isEmpty) return null;
    return nearby.first;
  }

  /// Save new landmark (supports user/AR creation)
  Future<void> saveLandmark(Landmark landmark) async {
    if (!db.isOpen) {
      throw StateError('Cannot save landmark: No active region SQLite connection.');
    }
    await db.insertLandmark(landmark);
    invalidateCache(); // Clear viewport cache since a new landmark appeared
    debugPrint('[LandmarkEngine] Saved landmark ID: ${landmark.id} (${landmark.name})');
  }

  /// Toggle favorited status of a landmark
  Future<void> toggleFavorite(String id) async {
    if (!db.isOpen) return;
    final l = await db.getById(id);
    if (l != null) {
      final updated = l.copyWith(
        isFavorite: !l.isFavorite,
        updatedAt: DateTime.now(),
      );
      await db.updateLandmark(updated);
      invalidateCache();
    }
  }
}
