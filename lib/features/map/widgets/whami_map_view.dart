import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/connectivity_status.dart';
import '../../../data/models/position_opinion.dart';
import '../../../data/models/landmark.dart';
import '../../../data/repositories/whami_repository.dart';
import '../../../data/services/maplibre_connectivity_service.dart';
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

  // The style passed to MapLibreMap must stay referentially/textually
  // stable across rebuilds: the maplibre_gl plugin diffs `styleString` as
  // part of its native options sync on every widget rebuild (not just via
  // our own _onActivePackChanged()/setStyle() calls), and force-reloads
  // the entire native style whenever it changes — wiping dynamically-added
  // layers outside our control. Recomputing it fresh in build() meant ANY
  // rebuild (e.g. a connectivity change, or the 5Hz+ position-tracking
  // notifyListeners() storm) could silently blank the map. So it's
  // computed once and only ever updated explicitly via setStyle().
  late String _styleString;

  // Last-applied values that drove the current style, used to detect real
  // changes in didUpdateWidget. Comparing widget.repository.X directly to
  // oldWidget.repository.X doesn't work here — both sides are the exact
  // same shared repository instance, so that comparison is always false.
  String _lastActivePackId = '';
  bool _lastIsOffline = false;

  // High-level MapEngine managing nested render pipelines
  final MapEngine _mapEngine = MapEngine();

  // Track whether opinions are currently being updated to prevent overlapping
  bool _isUpdatingOpinions = false;

  // Track whether a camera-idle refresh is in flight to prevent overlapping
  bool _isRefreshingCameraViewport = false;

  // Track whether pack layers are currently being (re)added to prevent
  // overlapping calls. onStyleLoadedCallback is driven by the native SDK
  // and can fire more than once for what's logically a single style load;
  // without this guard, two overlapping _loadPackLayers() calls can each
  // try to add the same named layer (setupLayers()'s own remove-then-add
  // step only protects against sequential re-calls, not truly concurrent
  // ones), which the native side rejects as "layer already exists".
  bool _isLoadingPackLayers = false;

  // Same reentrancy protection as _isLoadingPackLayers, for the base map
  // layers (roads/water/buildings/labels or raster fallback) added via
  // LayerEngine.setupBaseMapLayers().
  bool _isLoadingBaseMapLayers = false;

  // Whether we've already zoomed the camera in for the current tracking
  // session once a live GPS fix was confirmed (vs. sitting at the far-out
  // initial zoom for every subsequent pan while tracking).
  bool _hasZoomedForGpsConfirmation = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _lastActivePackId = widget.repository.activePackId;
    _lastIsOffline =
        widget.repository.connectivityMode == ConnectivityMode.offline;
    _styleString = jsonEncode(_buildStyleJson());
  }

  Map<String, dynamic> _buildStyleJson() {
    return _mapEngine.tile.generateStyle();
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

    // Re-assert this on every map view creation — MapLibre Native
    // (re-)activates its own connectivity receiver around map view init,
    // which can overwrite the one-time override set at engine startup
    // (MainActivity.kt) with the real (possibly offline) OS state.
    await MapLibreConnectivityService.forceConnected();

    if (widget.repository.activePackId.isEmpty) {
      final gps = widget.repository.sensors.gpsService;
      await gps.initialize();
      final pos = await gps.getCurrentPosition();
      if (pos != null && _controller != null && mounted) {
        _mapEngine.camera.centerOn(pos.latitude, pos.longitude, zoom: 12.5);
      }
    }

    // Re-sync now that the native map view actually exists — a pack can
    // already be active by this point (e.g. restored from a previous
    // session before the platform view finished initializing).
    // _onActivePackChanged() no-ops if called before _controller is set,
    // so nothing else would ever apply the correct style without this.
    await _onActivePackChanged();
  }

  void _onStyleLoaded() async {
    if (!mounted) return;
    // Base map first (roads/water/buildings sit below the overlays).
    await _loadBaseMapLayers();
    await _loadPackLayers();
    if (_packLoaded) {
      await _mapEngine.layer.updateVisibility(widget.layerVisibility);
      _updateOpinionsMarkers();
    }
  }

  /// Adds the base map (roads/water/buildings/labels, or the raster
  /// fallback) via the imperative controller API. Must be called after
  /// every style (re)load, since setStyle() tears down and replaces the
  /// whole native style, wiping anything added imperatively before it.
  Future<void> _loadBaseMapLayers() async {
    if (_controller == null) return;
    if (_isLoadingBaseMapLayers) return;
    _isLoadingBaseMapLayers = true;
    try {
      final activePack = widget.repository.activeRegionPack;
      final isOffline =
          widget.repository.connectivityMode == ConnectivityMode.offline;
      final localMBTilesUrl = activePack != null
          ? widget.repository.regionRepository.regionEngine.tileServer.baseUrl
          : null;
      await _mapEngine.layer.setupBaseMapLayers(
        isOffline: isOffline,
        localMBTilesUrl: localMBTilesUrl,
        rasterCacheUrl: widget.repository.rasterTileCacheService.baseUrl,
      );
    } catch (e) {
      debugPrint('Error loading base map layers: $e');
    } finally {
      _isLoadingBaseMapLayers = false;
    }
  }

  Future<void> _onActivePackChanged() async {
    if (_controller == null) {
      return;
    }

    final packId = widget.repository.activePackId;
    final isOffline =
        widget.repository.connectivityMode == ConnectivityMode.offline;

    if (packId.isEmpty) {
      setState(() {
        _packLoaded = false;
      });
      await _mapEngine.layer.clearLayers();
    }

    // Centering is now handled by WhamiRepository to ensure tracking is disabled

    final styleJson = _buildStyleJson();
    try {
      await _controller!.setStyle(jsonEncode(styleJson));
      _styleString = jsonEncode(styleJson);
    } catch (e) {
      debugPrint('Error loading map style on pack activation: $e');
    }

    _lastActivePackId = packId;
    _lastIsOffline = isOffline;
  }

  /// Triggered once the camera settles (not on every intermediate move frame).
  /// LandmarkEngine viewport cache intercepts coordinates to guarantee
  /// sub-millisecond cache hits.
  void _onMapCameraChanged() async {
    if (_controller == null || !_packLoaded) return;
    if (_isRefreshingCameraViewport) return;
    _isRefreshingCameraViewport = true;
    try {
      final bounds = await _controller!.getVisibleRegion();

      // Update central MapRepository coordinate state
      widget.repository.mapRepository.updateBounds(
        bounds.southwest.latitude,
        bounds.southwest.longitude,
        bounds.northeast.latitude,
        bounds.northeast.longitude,
      );

      widget.repository.mapRepository.updateZoom(
        _controller!.cameraPosition?.zoom ?? 8.0,
      );
      if (_controller!.cameraPosition != null) {
        widget.repository.mapRepository.updateCenter(
          _controller!.cameraPosition!.target.latitude,
          _controller!.cameraPosition!.target.longitude,
        );
      }

      // Fetch from SQLite (or LandmarkEngine cache)
      final visible = await widget.repository.landmarkRepository
          .getVisibleLandmarks(
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
    } catch (_) {
    } finally {
      _isRefreshingCameraViewport = false;
    }
  }

  @override
  void didUpdateWidget(WhamiMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.repository.isTracking && widget.repository.isTracking) {
      _isUserPanning = false;
      _hasZoomedForGpsConfirmation = false;
    }

    // NOTE: widget.repository and oldWidget.repository are the exact same
    // shared singleton instance, so comparing fields directly between them
    // always reads the same (current) value on both sides. The real
    // previous state is tracked separately in _lastActivePackId/_lastIsOffline.
    final currentPackId = widget.repository.activePackId;
    final currentIsOffline =
        widget.repository.connectivityMode == ConnectivityMode.offline;

    if (currentPackId != _lastActivePackId || currentIsOffline != _lastIsOffline) {
      _onActivePackChanged();
    } else if (_packLoaded) {
      _mapEngine.layer.updateVisibility(widget.layerVisibility);
    }
    if (_packLoaded) _updateOpinionsMarkers();
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

      if (!_hasZoomedForGpsConfirmation) {
        PositionOpinion? gpsOpinion;
        try {
          gpsOpinion = widget.repository.getPositionOpinions().firstWhere(
            (o) => o.sourceType == 'gps',
          );
        } catch (_) {
          gpsOpinion = null;
        }
        final gpsConfirmed =
            gpsOpinion != null && gpsOpinion.status != 'unavailable';

        if (gpsConfirmed) {
          // Matches the mbtiles source's actual maxzoom (14) — avoids
          // upscaled/overzoomed tiles at higher camera zoom levels.
          _mapEngine.camera.centerOn(
            whamiPos.latitude,
            whamiPos.longitude,
            zoom: 9.0,
          );
          _hasZoomedForGpsConfirmation = true;
          return;
        }
      }

      _mapEngine.camera.panTo(whamiPos.latitude, whamiPos.longitude);
    }
  }

  Future<void> _loadPackLayers() async {
    if (_controller == null) return;
    // onStyleLoadedCallback can fire more than once for one logical style
    // load; a second overlapping call here is redundant, not new
    // information, so it's simply dropped rather than queued/retried.
    if (_isLoadingPackLayers) return;
    _isLoadingPackLayers = true;

    try {
      final packId = widget.repository.activePackId;
      if (packId.isEmpty) {
        setState(() {
          _packLoaded = false;
        });
        await _mapEngine.layer.clearLayers();
        return;
      }

      // Feed local SQLite landmarks inside current view
      final bounds = await _controller!.getVisibleRegion();
      final visible = await widget.repository.landmarkRepository
          .getVisibleLandmarks(
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
        magneticGeo:
            emptyGeo, // magnetic baseline generated dynamically in fusion engine if needed
        seamapGeo: emptyGeo,
      );

      setState(() {
        _packLoaded = true;
      });

      _mapEngine.layer.updateVisibility(widget.layerVisibility);
    } catch (e) {
      debugPrint('Error loading maplibre layers: $e');
    } finally {
      _isLoadingPackLayers = false;
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
    } catch (e) {
      debugPrint('[WhamiMapView] _updateOpinionsMarkers failed: $e');
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
            onCameraIdle: _onMapCameraChanged,
            styleString: _styleString,
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
    if (widget.layerVisibility['landmarks'] == true)
      activeLayers.add('landmarks');
    if (widget.layerVisibility['seamap'] == true) activeLayers.add('seamap');
    if (widget.layerVisibility['magnetic'] == true)
      activeLayers.add('magnetic');

    if (activeLayers.isEmpty) return 'offline mode (no layers)';
    return activeLayers.join(' · ');
  }
}
