import 'package:flutter/foundation.dart';
import '../models/landmark.dart';

class MapRepository extends ChangeNotifier {
  String _currentStyleName = 'WHAMI Light';
  String _activeTileSource = '';
  double _currentZoom = 8.0;
  double _centerLatitude = 37.8087;
  double _centerLongitude = -122.4098;
  List<double> _currentBounds = [0.0, 0.0, 0.0, 0.0]; // [minLat, minLng, maxLat, maxLng]
  List<Landmark> _visibleLandmarks = [];

  String get currentStyleName => _currentStyleName;
  String get activeTileSource => _activeTileSource;
  double get currentZoom => _currentZoom;
  double get centerLatitude => _centerLatitude;
  double get centerLongitude => _centerLongitude;
  List<double> get currentBounds => _currentBounds;
  List<Landmark> get visibleLandmarks => _visibleLandmarks;

  /// Update map zoom index
  void updateZoom(double zoom) {
    if (_currentZoom == zoom) return;
    _currentZoom = zoom;
    notifyListeners();
  }

  /// Update active bounding box coordinates
  void updateBounds(double minLat, double minLng, double maxLat, double maxLng) {
    _currentBounds = [minLat, minLng, maxLat, maxLng];
    notifyListeners();
  }

  /// Update center focal coordinates
  void updateCenter(double lat, double lng) {
    if (_centerLatitude == lat && _centerLongitude == lng) return;
    _centerLatitude = lat;
    _centerLongitude = lng;
    notifyListeners();
  }

  /// Update list of landmarks visible in the current viewport
  void updateVisibleLandmarks(List<Landmark> landmarks) {
    _visibleLandmarks = landmarks;
    notifyListeners();
  }

  /// Set the active tile source
  void updateActiveTileSource(String path) {
    if (_activeTileSource == path) return;
    _activeTileSource = path;
    notifyListeners();
  }

  /// Set active styling options
  void updateStyleName(String style) {
    if (_currentStyleName == style) return;
    _currentStyleName = style;
    notifyListeners();
  }
}
