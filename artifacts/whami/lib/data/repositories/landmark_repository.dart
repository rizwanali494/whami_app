import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/landmark.dart';
import '../services/landmark_engine.dart';

class LandmarkRepository extends ChangeNotifier {
  final LandmarkEngine landmarkEngine;

  LandmarkRepository({required this.landmarkEngine});

  /// Get visible landmarks within bounds (uses cache inside LandmarkEngine)
  Future<List<Landmark>> getVisibleLandmarks(
    double minLat,
    double minLng,
    double maxLat,
    double maxLng, {
    int limit = 500,
  }) async {
    return await landmarkEngine.getVisibleLandmarks(minLat, minLng, maxLat, maxLng, limit: limit);
  }

  /// Search landmarks by query string
  Future<List<Landmark>> searchLandmarks(String query) async {
    final results = await landmarkEngine.searchLandmarks(query);
    notifyListeners();
    return results;
  }

  /// Get nearby sorted landmarks
  Future<List<Landmark>> getNearbyLandmarks(double lat, double lng, double radiusMeters) async {
    return await landmarkEngine.getNearbyLandmarks(lat, lng, radiusMeters);
  }

  /// Match closest physical landmark for position anchoring
  Future<Landmark?> matchNearestLandmark(double lat, double lng, {double maxDistanceMeters = 5000.0}) async {
    return await landmarkEngine.matchNearestLandmark(lat, lng, maxDistanceMeters: maxDistanceMeters);
  }

  /// Save new user/AR landmark (inserted directly into unified active landmarks.sqlite)
  Future<void> saveUserLandmark(Landmark landmark) async {
    await landmarkEngine.saveLandmark(landmark);
    notifyListeners();
  }

  /// Toggle favorited status of a landmark
  Future<void> toggleFavorite(String id) async {
    await landmarkEngine.toggleFavorite(id);
    notifyListeners();
  }
}
