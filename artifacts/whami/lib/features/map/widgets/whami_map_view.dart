import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/connectivity_status.dart';
import '../../../data/models/position_opinion.dart';
import '../../../data/models/landmark.dart';
import '../../../data/repositories/whami_repository.dart';
import '../services/map_engine.dart';

class WhamiMapView extends StatefulWidget {
  final List<PositionOpinion> opinions;
  final Map<String, bool> layerVisibility;
  final WhamiRepository repository;

  const WhamiMapView({
    super.key,
    required this.opinions,
    required this.layerVisibility,
    required this.repository,
  });

  @override
  State<WhamiMapView> createState() => _WhamiMapViewState();
}

class _WhamiMapViewState extends State<WhamiMapView>
    with SingleTickerProviderStateMixin {
  MapLibreMapController? _controller;
  bool _packLoaded = false;
  bool _isUserPanning = false;
  late final AnimationController _pulseController;
  
  // High-level MapEngine managing nested render pipelines
  final MapEngine _mapEngine = MapEngine();

  // Track whether opinions are currently being updated to prevent overlapping
  bool _isUpdatingOpinions = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapEngine.detach();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    _mapEngine.attach(controller);
    _controller!.addListener(_onMapCameraChanged);

    if (widget.repository.activePackId.isEmpty) {
      final gps = widget.repository.sensors.gpsService;
      await gps.initialize();
      final pos = await gps.getCurrentPosition();
      if (pos != null && _controller != null && mounted) {
        _mapEngine.camera.centerOn(pos.latitude, pos.longitude, zoom: 12.5);
      }
    }
  }

  void _onStyleLoaded() async {
    if (!mounted) return;
    await _loadPackLayers();
  }

  void _onActivePackChanged() async {
    if (_controller == null) return;

    final packId = widget.repository.activePackId;
    final isOffline = widget.repository.connectivityMode == ConnectivityMode.offline;

    if (packId.isEmpty) {
      setState(() {
        _packLoaded = false;
      });
      await _mapEngine.layer.clearLayers();
      final styleJson = _mapEngine.tile.generateStyle(
        isOffline: isOffline,
        localMBTilesUrl: null,
      );
      try {
        await _controller!.setStyle(jsonEncode(styleJson));
      } catch (e) {
        debugPrint('Error resetting map style: $e');
      }
      return;
    }

    final activePack = widget.repository.getRegionPackById(packId);
    final localMBTilesUrl = activePack != null
        ? widget.repository.regionRepository.regionEngine.tileServer.baseUrl
        : null;

    final styleJson = _mapEngine.tile.generateStyle(
      isOffline: isOffline,
      localMBTilesUrl: localMBTilesUrl,
    );

    // Centering is now handled by WhamiRepository to ensure tracking is disabled

    try {
      await _controller!.setStyle(jsonEncode(styleJson));
    } catch (e) {
      debugPrint('Error loading map style on pack activation: $e');
    }
  }

  /// Triggered on every map movement. LandmarkEngine viewport cache intercepts
  /// coordinates to guarantee sub-millisecond cache hits.
  void _onMapCameraChanged() async {
    if (_controller == null || !_packLoaded) return;
    try {
      final bounds = await _controller!.getVisibleRegion();
      
      // Update central MapRepository coordinate state
      widget.repository.mapRepository.updateBounds(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      );

      widget.repository.mapRepository.updateZoom(_controller!.cameraPosition?.zoom ?? 8.0);
      if (_controller!.cameraPosition != null) {
        widget.repository.mapRepository.updateCenter(
          _controller!.cameraPosition!.target.latitude,
          _controller!.cameraPosition!.target.longitude,
        );
      }

      // Fetch from SQLite (or LandmarkEngine cache)
      final visible = await widget.repository.landmarkRepository.getVisibleLandmarks(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      );

      // Save to MapRepository state
      widget.repository.mapRepository.updateVisibleLandmarks(visible);

      // Reload landmarks symbol GeoJSON
      final geo = _landmarksToGeoJson(visible);
      await _controller!.setGeoJsonSource('landmarks', geo);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(WhamiMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.repository.isTracking && widget.repository.isTracking) {
      _isUserPanning = false;
    }

    if (widget.repository.activePackId != oldWidget.repository.activePackId) {
      _onActivePackChanged();
    } else {
      _mapEngine.layer.updateVisibility(widget.layerVisibility);
    }
    _updateOpinionsMarkers();
    _handleMapCentering();
  }

  void _handleMapCentering() {
    if (_controller == null) return;

    if (widget.repository.mapCenterLat != null &&
        widget.repository.mapCenterLng != null) {
      final targetLat = widget.repository.mapCenterLat!;
      final targetLng = widget.repository.mapCenterLng!;

      _mapEngine.camera.centerOn(targetLat, targetLng, zoom: 14.5);

      widget.repository.mapCenterLat = null;
      widget.repository.mapCenterLng = null;
      _isUserPanning = false;
    } else if (widget.repository.isTracking && !_isUserPanning) {
      final whamiPos = widget.repository.getTrustedPosition();
      _mapEngine.camera.panTo(whamiPos.latitude, whamiPos.longitude);
    }
  }

  Future<void> _loadPackLayers() async {
    if (_controller == null) return;

    final packId = widget.repository.activePackId;
    if (packId.isEmpty) {
      setState(() {
        _packLoaded = false;
      });
      await _mapEngine.layer.clearLayers();
      return;
    }

    try {
      // Feed local SQLite landmarks inside current view
      final bounds = await _controller!.getVisibleRegion();
      final visible = await widget.repository.landmarkRepository.getVisibleLandmarks(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      );

      final landmarksGeo = _landmarksToGeoJson(visible);
      final emptyGeo = {'type': 'FeatureCollection', 'features': []};

      // Set up map engine symbol/line/circle layers
      await _mapEngine.layer.setupLayers(
        packId: packId,
        landmarksGeo: landmarksGeo,
        magneticGeo: emptyGeo, // magnetic baseline generated dynamically in fusion engine if needed
        seamapGeo: emptyGeo,
      );

      setState(() {
        _packLoaded = true;
      });

      _mapEngine.layer.updateVisibility(widget.layerVisibility);
    } catch (e) {
      debugPrint('Error loading maplibre layers: $e');
    }
  }

  Map<String, dynamic> _landmarksToGeoJson(List<Landmark> landmarks) {
    return {
      'type': 'FeatureCollection',
      'features': landmarks.map((l) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [l.longitude, l.latitude],
          },
          'properties': {
            'name': l.name,
            'landmark_type': l.category,
            'confidence': l.confidence,
            'saved': l.saved,
          },
        };
      }).toList(),
    };
  }

  void _updateOpinionsMarkers() async {
    if (_controller == null || _isUpdatingOpinions) return;
    _isUpdatingOpinions = true;

    try {
      final showOpinions = widget.layerVisibility['opinions'] == true;
      await _mapEngine.overlay.drawOpinions(widget.opinions, showOpinions);
    } finally {
      _isUpdatingOpinions = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePack = widget.repository.activeRegionPack;
    
    // Pick center coords or fallback
    LatLng centerCoords = const LatLng(37.8087, -122.4098);
    if (activePack?.metadata != null) {
      final bounds = activePack!.metadata!.bounds;
      if (bounds.length == 4 && bounds[0] != 0 && bounds[1] != 0) {
        // [minLat, minLon, maxLat, maxLon]
        final lat = (bounds[0] + bounds[2]) / 2.0;
        final lng = (bounds[1] + bounds[3]) / 2.0;
        centerCoords = LatLng(lat, lng);
      }
    }

    final isOffline = widget.repository.connectivityMode == ConnectivityMode.offline;
    
    // Mount style sheet through tile engine
    final localMBTilesUrl = activePack != null
        ? widget.repository.regionRepository.regionEngine.tileServer.baseUrl
        : null;

    final styleJson = _mapEngine.tile.generateStyle(
      isOffline: isOffline,
      localMBTilesUrl: localMBTilesUrl,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (widget.repository.isTracking && !_isUserPanning) {
              setState(() {
                _isUserPanning = true;
              });
            }
          },
          child: MapLibreMap(
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
            initialCameraPosition: CameraPosition(
              target: centerCoords,
              zoom: 8,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedCallback: _onStyleLoaded,
            styleString: jsonEncode(styleJson),
            myLocationEnabled: true,
            myLocationTrackingMode: MyLocationTrackingMode.tracking,
            zoomGesturesEnabled: true,
            dragEnabled: true,
            compassEnabled: true,
            scaleControlEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            trackCameraPosition: true,
            logoEnabled: false,
          ),
        ),

        if (_packLoaded)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xCC0D1117),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.layers, size: 10, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 4),
                  Text(
                    _buildCoverageOverlayLabel(),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF4CAF50),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _buildCoverageOverlayLabel() {
    final List<String> activeLayers = [];
    if (widget.layerVisibility['landmarks'] == true) activeLayers.add('landmarks');
    if (widget.layerVisibility['seamap'] == true) activeLayers.add('seamap');
    if (widget.layerVisibility['magnetic'] == true) activeLayers.add('magnetic');

    if (activeLayers.isEmpty) return 'offline mode (no layers)';
    return activeLayers.join(' · ');
  }
}
