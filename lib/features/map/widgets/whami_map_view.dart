import 'dart:async';
import 'dart:convert';
import 'dart:math' show Point;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/config/map_basemap_style.dart';
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

  // Last-applied pack id, used to detect a real pack change in
  // didUpdateWidget. Comparing widget.repository.activePackId directly to
  // oldWidget.repository.activePackId doesn't work here — both sides are
  // the exact same shared repository instance, so that comparison is
  // always false. Connectivity flips are deliberately NOT tracked here
  // anymore: every base-map source (local vector tiles when a pack is
  // active, the cache-backed raster proxy otherwise) already works
  // identically online or offline, so forcing a full setStyle() teardown
  // on every connectivity change was pure churn — and it landed at exactly
  // the moment MapLibre Native's own connectivity receiver may have
  // briefly clobbered the forceConnected() override (see
  // MapLibreConnectivityService), turning a harmless flip into a visibly
  // broken map.
  String _lastActivePackId = '';
  late MapBasemapStyle _lastBasemapStyle;

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

  /// One-shot camera fit when Ghost Pin first appears.
  bool _hasFittedGhostPair = false;

  /// Native MapLibre location puck — Android only. iOS CoreLocation path
  /// SIGABRTs on recent simulators; blue G comes from GeoJSON instead.
  bool _myLocationEnabled = false;

  /// Blocks overlay updates until [onStyleLoadedCallback] finishes setup.
  /// Calling add/setGeoJson before that marks layers "ready" incorrectly and
  /// permanently breaks pins/lines (STYLE_NOT_READY → source not found spam).
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _lastActivePackId = widget.repository.activePackId;
    _lastBasemapStyle = widget.repository.mapBasemapStyle;
    _styleString = _resolveStyleString();
  }

  /// Always embed raster via [RasterTileCacheService] (correct UA).
  /// Pack vector layers are added on top in [_loadBaseMapLayers].
  String _resolveStyleString() {
    final cacheUrl = widget.repository.rasterTileCacheService.baseUrl;
    final glyphsUrl = widget.repository.glyphServer.baseUrl;
    return jsonEncode(
      _mapEngine.tile.generateStyle(
        glyphsUrl: glyphsUrl.isNotEmpty ? glyphsUrl : null,
        includeRasterBasemap: true,
        rasterCacheUrl: cacheUrl.isNotEmpty ? cacheUrl : null,
        basemapStyle: widget.repository.mapBasemapStyle,
      ),
    );
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
        _mapEngine.camera.centerOn(pos.latitude, pos.longitude, zoom: 14.0);
      }
    }

    // Re-sync style once the platform view exists (pack restore / cache URL).
    final packId = widget.repository.activePackId;
    if (packId != _lastActivePackId ||
        !_styleString.contains('127.0.0.1')) {
      await _onActivePackChanged();
    }
  }

  void _onStyleLoaded() async {
    if (!mounted) return;
    _styleReady = false;
    _mapEngine.overlay.resetGhostLayers();
    _mapEngine.overlay.resetCrossfireLayers();
    _mapEngine.overlay.resetFlightPlanLayers();
    _mapEngine.overlay.resetRangeRingLayers();
    _mapEngine.overlay.resetOpinionLayers();

    // Base map first (roads sit under overlays) — same path as shipped build.
    await _loadBaseMapLayers();
    if (widget.repository.activePackId.isNotEmpty) {
      await _loadPackLayers();
      if (_packLoaded) {
        await _mapEngine.layer.updateVisibility(widget.layerVisibility);
      }
    }

    if (!mounted) return;
    _styleReady = true;

    await _updateOpinionsMarkers();
    await _updateGhostLie();
    await _updateCrossfire();
    await _updateFlightPlan();
    await _updateRangeRings();
    await _updateTruthTrails();
    await _updateSpoofHeat();

    if (!mounted ||
        _myLocationEnabled ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted && !_myLocationEnabled) {
      setState(() => _myLocationEnabled = true);
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
      final localMBTilesUrl = activePack != null
          ? widget.repository.regionRepository.regionEngine.tileServer.baseUrl
          : null;

      // Connectivity only matters for the no-pack raster fallback (the
      // brief window before RasterTileCacheService finishes starting) — with
      // a pack active the base map is served entirely from the local
      // MBTiles vector tile server, so real connectivity is irrelevant.
      final isOffline =
          activePack == null &&
          widget.repository.connectivityMode == ConnectivityMode.offline;

      final cacheUrl = widget.repository.rasterTileCacheService.baseUrl;
      await _mapEngine.layer.setupBaseMapLayers(
        isOffline: isOffline,
        localMBTilesUrl: localMBTilesUrl,
        rasterCacheUrl: cacheUrl.isNotEmpty ? cacheUrl : null,
        // Raster is baked into style JSON when the cache proxy is ready.
        rasterAlreadyInStyle: cacheUrl.isNotEmpty,
        basemapStyle: widget.repository.mapBasemapStyle,
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

    if (packId.isEmpty) {
      setState(() {
        _packLoaded = false;
      });
      await _mapEngine.layer.clearLayers();
    }

    final nextStyle = _resolveStyleString();
    try {
      await _controller!.setStyle(nextStyle);
      _styleString = nextStyle;
    } catch (e) {
      debugPrint('Error loading map style on pack activation: $e');
    }

    _lastActivePackId = packId;
    _lastBasemapStyle = widget.repository.mapBasemapStyle;
  }

  Future<void> _onBasemapStyleChanged() async {
    if (_controller == null) return;
    _styleReady = false;
    final nextStyle = _resolveStyleString();
    try {
      await _controller!.setStyle(nextStyle);
      _styleString = nextStyle;
    } catch (e) {
      debugPrint('Error loading map style on basemap change: $e');
    }
    _lastBasemapStyle = widget.repository.mapBasemapStyle;
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
      _hasFittedGhostPair = false;
    }

    // NOTE: widget.repository and oldWidget.repository are the exact same
    // shared singleton instance, so comparing fields directly between them
    // always reads the same (current) value on both sides. The real
    // previous state is tracked separately in _lastActivePackId.
    final currentPackId = widget.repository.activePackId;
    final basemap = widget.repository.mapBasemapStyle;

    if (currentPackId != _lastActivePackId) {
      _styleReady = false;
      _onActivePackChanged();
    } else if (basemap != _lastBasemapStyle) {
      _onBasemapStyleChanged();
    } else if (_packLoaded) {
      _mapEngine.layer.updateVisibility(widget.layerVisibility);
    }
    if (_styleReady) {
      _updateOpinionsMarkers();
      _updateGhostLie();
      _updateCrossfire();
      _updateFlightPlan();
      _updateRangeRings();
      _updateTruthTrails();
      _updateSpoofHeat();
    }
    _handleMapCentering();
  }

  Future<void> _updateTruthTrails() async {
    if (!_styleReady || _controller == null) return;
    final tm = widget.repository.truthMode;
    await _mapEngine.overlay.drawTruthTrails(
      visible: tm.enabled,
      trusted: tm.trustedTrail,
      claimed: tm.claimedTrail,
    );
  }

  Future<void> _updateSpoofHeat() async {
    if (!_styleReady || _controller == null) return;
    final show = widget.layerVisibility['spoofHeat'] ?? false;
    final cells = widget.repository.spoofHeatCells;
    await _mapEngine.overlay.drawSpoofHeat(
      visible: show,
      cells: cells
          .map(
            (c) => (
              lat: c.latitude,
              lng: c.longitude,
              radiusM: c.radiusM,
              intensity: c.intensity,
              label: c.label,
            ),
          )
          .toList(),
    );
  }

  Future<void> _updateFlightPlan() async {
    if (!_styleReady || _controller == null) return;
    final plan = widget.repository.activeFlightPlan;
    final wps = plan?.waypoints ?? const [];
    final progress = widget.repository.routeProgress;
    await _mapEngine.overlay.drawFlightPlan(
      visible: wps.isNotEmpty,
      waypoints: wps
          .map(
            (w) => (
              id: w.id,
              name: w.name,
              lat: w.latitude,
              lng: w.longitude,
            ),
          )
          .toList(),
      progressLat: progress?.nearestLat,
      progressLng: progress?.nearestLng,
    );
  }

  void _dropRoutePin(LatLng coordinates) {
    if (!widget.repository.flightPlanEditMode) return;
    widget.repository.addFlightWaypoint(
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
    );
  }

  void _onMapClick(Point<double> point, LatLng coordinates) {
    _dropRoutePin(coordinates);
  }

  void _onMapLongClick(Point<double> point, LatLng coordinates) {
    _dropRoutePin(coordinates);
  }

  Future<void> _updateRangeRings() async {
    if (!_styleReady || _controller == null) return;
    final show = widget.layerVisibility['rangeRings'] ?? true;
    double? lat = widget.repository.trustedLat;
    double? lng = widget.repository.trustedLng;
    if (lat == null || lng == null) {
      for (final o in widget.opinions) {
        if (o.sourceType == 'gps' && o.status != 'unavailable') {
          lat = o.latitude;
          lng = o.longitude;
          break;
        }
      }
    }
    await _mapEngine.overlay.drawRangeRings(
      visible: show && lat != null && lng != null,
      centerLat: lat,
      centerLng: lng,
      radiiKm: const [5, 10, 20, 40],
    );
  }

  Future<void> _updateCrossfire() async {
    if (!_styleReady || _controller == null) return;
    final cf = widget.repository.crossfire;
    await _mapEngine.overlay.drawCrossfire(
      visible: cf.visible,
      trustedLat: cf.trustedLat,
      trustedLng: cf.trustedLng,
      witnesses: cf.witnesses
          .map(
            (w) => (
              id: w.id,
              lat: w.latitude,
              lng: w.longitude,
              agrees: w.agrees,
              isOutlier: w.isOutlier,
              shortCode: w.shortCode,
            ),
          )
          .toList(),
    );
  }

  Future<void> _updateGhostLie() async {
    if (!_styleReady || _controller == null) return;
    final repo = widget.repository;
    final show = repo.showGhostPin;
    await _mapEngine.overlay.drawGhostLie(
      visible: show,
      gpsLat: repo.gpsClaimLat,
      gpsLng: repo.gpsClaimLng,
      trustedLat: repo.trustedLat,
      trustedLng: repo.trustedLng,
      lieDistanceM: repo.lieDistanceM,
    );
    if (show &&
        !_hasFittedGhostPair &&
        repo.gpsClaimLat != null &&
        repo.gpsClaimLng != null &&
        repo.trustedLat != null &&
        repo.trustedLng != null) {
      _hasFittedGhostPair = true;
      _isUserPanning = true; // don't fight recenter while showing the lie
      // Continental lie distances (emulator GPS jump) make fitPair zoom to
      // the whole planet — soft/unreadable. Stay street-level on trusted;
      // the Lie line badge already shows the km figure.
      final distM = repo.lieDistanceM ?? 0;
      if (distM > 50000) {
        _mapEngine.camera.centerOn(
          repo.trustedLat!,
          repo.trustedLng!,
          zoom: 14.5,
        );
      } else {
        _mapEngine.camera.fitPair(
          repo.gpsClaimLat!,
          repo.gpsClaimLng!,
          repo.trustedLat!,
          repo.trustedLng!,
        );
      }
    } else if (!show) {
      _hasFittedGhostPair = false;
    }
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
      // Follow the live GPS pin (blue G) — not the trusted/lock pin (green),
      // which can sit on a locked SF landmark while you are elsewhere.
      // When Ghost Pin is showing, keep the dual-pin framing (don't yank to lock).
      if (widget.repository.showGhostPin) return;

      final follow = _followTarget();
      if (follow == null) return;

      if (!_hasZoomedForGpsConfirmation) {
        _mapEngine.camera.centerOn(follow.$1, follow.$2, zoom: 14.0);
        _hasZoomedForGpsConfirmation = true;
        return;
      }

      _mapEngine.camera.panTo(follow.$1, follow.$2);
    }
  }

  /// Prefer live GPS coords; fall back to fused trusted only if GPS is gone.
  /// Returns null when there is no real fix (never follows a fabricated city).
  (double, double)? _followTarget() {
    try {
      final gps = widget.repository.getPositionOpinions().firstWhere(
        (o) => o.sourceType == 'gps' && o.status != 'unavailable',
      );
      return (gps.latitude, gps.longitude);
    } catch (_) {}
    final trusted = widget.repository.getTrustedPosition();
    if (trusted.status == 'unavailable') return null;
    return (trusted.latitude, trusted.longitude);
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

  Future<void> _updateOpinionsMarkers() async {
    if (!_styleReady || _controller == null || _isUpdatingOpinions) return;
    _isUpdatingOpinions = true;

    try {
      final showOpinions = widget.layerVisibility['opinions'] == true;
      await _mapEngine.overlay.drawOpinions(widget.opinions, showOpinions);
      final gps = widget.repository.sensors.gpsService.lastReading;
      if (gps != null && showOpinions) {
        await _mapEngine.overlay.drawLiveGps(
          lat: gps.latitude,
          lng: gps.longitude,
          accuracyM: gps.accuracy,
        );
      }
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
            onMapClick: _onMapClick,
            onMapLongClick: _onMapLongClick,
            styleString: _styleString,
            // Empty order: GeoJSON overlays only (AnnotationManager races style
            // load on both platforms and was blanking pins/lines).
            annotationOrder: const [],
            annotationConsumeTapEvents: const [AnnotationType.symbol],
            myLocationEnabled: _myLocationEnabled,
            myLocationTrackingMode: _myLocationEnabled
                ? MyLocationTrackingMode.tracking
                : MyLocationTrackingMode.none,
            zoomGesturesEnabled: true,
            dragEnabled: true,
            compassEnabled: true,
            scaleControlEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            trackCameraPosition: true,
            logoEnabled: false,
            attributionButtonMargins: const Point(8, 8),
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
