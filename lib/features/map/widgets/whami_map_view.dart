import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../../core/constants/connectivity_status.dart';
import '../../../data/models/position_opinion.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/whami_repository.dart';
import '../../../core/map/offline_style.dart';

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
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    _controller!.addListener(_onMapChanged);

    if (widget.repository.activePackId.isEmpty) {
      final gps = widget.repository.sensors.gpsService;
      await gps.initialize();
      final pos = await gps.getCurrentPosition();
      if (pos != null && _controller != null && mounted) {
        _controller!.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 12.5),
        );
      }
    }

    await _loadPackLayers();
  }

  void _onMapChanged() {
    // Redraw markers/overlays if camera moves (if using screen projections)
  }

  @override
  void didUpdateWidget(WhamiMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reset panning state if tracking was just turned on
    if (!oldWidget.repository.isTracking && widget.repository.isTracking) {
      _isUserPanning = false;
    }

    if (widget.repository.activePackId != oldWidget.repository.activePackId) {
      _loadPackLayers();
    } else {
      _updateLayersVisibility();
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

      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(targetLat, targetLng), 14.5),
      );

      widget.repository.mapCenterLat = null;
      widget.repository.mapCenterLng = null;
      _isUserPanning = false;
    } else if (widget.repository.isTracking && !_isUserPanning) {
      final whamiPos = widget.repository.getTrustedPosition();
      _controller!.animateCamera(
        CameraUpdate.newLatLng(LatLng(whamiPos.latitude, whamiPos.longitude)),
      );
    }
  }

  Future<void> _loadPackLayers() async {
    if (_controller == null) return;

    final packId = widget.repository.activePackId;
    if (packId.isEmpty) {
      setState(() {
        _packLoaded = false;
      });
      return;
    }

    try {
      final storage = widget.repository.storage;

      // Read local geojson files
      final landmarks = await storage.loadGeoJson(packId, 'landmarks.geojson');
      final magnetic = await storage.loadGeoJson(packId, 'magnetic.geojson');
      final seamap = await storage.loadGeoJson(packId, 'seamap.geojson');

      // Clear existing layers & sources if already loaded
      try {
        await _controller!.removeLayer('landmark-layer');
        await _controller!.removeSource('landmarks');
        await _controller!.removeLayer('magnetic-layer');
        await _controller!.removeSource('magnetic');
        await _controller!.removeLayer('seamap-layer');
        await _controller!.removeSource('seamap');
      } catch (_) {}

      // Add to map as sources
      await _controller!.addGeoJsonSource('landmarks', landmarks);
      await _controller!.addSymbolLayer(
        'landmarks',
        'landmark-layer',
        const SymbolLayerProperties(
          iconImage: 'landmark-icon',
          iconSize: 1.0,
          textField: '{name}',
          textColor: '#FFFFFF',
          textSize: 10,
          textOffset: [0, 1.5],
        ),
      );

      await _controller!.addGeoJsonSource('magnetic', magnetic);
      await _controller!.addCircleLayer(
        'magnetic',
        'magnetic-layer',
        const CircleLayerProperties(
          circleRadius: 5.0,
          circleColor: '#E24B4A',
          circleOpacity: 0.6,
        ),
      );

      await _controller!.addGeoJsonSource('seamap', seamap);
      await _controller!.addLineLayer(
        'seamap',
        'seamap-layer',
        const LineLayerProperties(lineColor: '#00E5FF', lineWidth: 3.0),
      );

      setState(() {
        _packLoaded = true;
      });

      _updateLayersVisibility();
    } catch (e) {
      debugPrint('Error loading maplibre layers: $e');
    }
  }

  void _updateLayersVisibility() {
    if (_controller == null || !_packLoaded) return;

    final landmarksVisible = widget.layerVisibility['landmarks'] == true;
    final magneticVisible = widget.layerVisibility['magnetic'] == true;
    final seamapVisible = widget.layerVisibility['seamap'] == true;

    try {
      _controller!.setLayerProperties(
        'landmark-layer',
        SymbolLayerProperties(
          visibility: landmarksVisible ? 'visible' : 'none',
        ),
      );
      _controller!.setLayerProperties(
        'magnetic-layer',
        CircleLayerProperties(visibility: magneticVisible ? 'visible' : 'none'),
      );
      _controller!.setLayerProperties(
        'seamap-layer',
        LineLayerProperties(visibility: seamapVisible ? 'visible' : 'none'),
      );
    } catch (e) {
      //
    }
  }

  void _updateOpinionsMarkers() async {
    if (_controller == null || _isUpdatingOpinions) return;
    _isUpdatingOpinions = true;

    try {
      // clearCircles and clearSymbols only affect markers added via addCircle/addSymbol,
      // not the ones added via Layers (like landmarks, magnetic).
      await _controller!.clearCircles();
      await _controller!.clearSymbols();

      if (widget.layerVisibility['opinions'] != true) return;

      // Make a copy to avoid ConcurrentModificationError while awaiting
      final currentOpinions = List<PositionOpinion>.from(widget.opinions);

      for (final op in currentOpinions) {
        if (op.confidence == 0 || !op.isActive) continue;

        final color = _colorForSource(op.sourceType);
        final hexColor =
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

        await _controller!.addCircle(
          CircleOptions(
            geometry: LatLng(op.latitude, op.longitude),
            circleRadius: op.sourceType == 'whami' ? 12.0 : 8.0,
            circleColor: hexColor,
            circleOpacity: 0.85,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 1.5,
          ),
        );

        await _controller!.addSymbol(
          SymbolOptions(
            geometry: LatLng(op.latitude, op.longitude),
            textField: op.shortCode,
            textColor: '#FFFFFF',
            textSize: 9.0,
            textAnchor: 'center',
          ),
        );
      }
    } finally {
      _isUpdatingOpinions = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePackId = widget.repository.activePackId;
    final centerCoords = activePackId.isNotEmpty
        ? (activePackId == 'sf_bay'
              ? const LatLng(37.8087, -122.4098)
              : const LatLng(39.0968, -120.0324)) // simple coordinate match
        : const LatLng(37.8087, -122.4098);

    final isOffline =
        widget.repository.connectivityMode == ConnectivityMode.offline;
    final styleJson = OfflineStyle.generate(isOffline: isOffline);

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

        // ── Offline status label overlay ──
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

  Color _colorForSource(String sourceType) {
    switch (sourceType) {
      case 'whami':
        return AppColors.whami;
      case 'gps':
        return AppColors.gps;
      case 'landmark':
        return AppColors.landmark;
      case 'magnetic':
        return AppColors.magnetic;
      case 'sextant':
        return AppColors.sextant;
      case 'imu':
        return AppColors.imu;
      default:
        return Colors.white;
    }
  }
}

class MapLegendRow extends StatelessWidget {
  final List<PositionOpinion> opinions;

  const MapLegendRow({super.key, required this.opinions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: opinions.map((op) {
        if (op.confidence == 0) return const SizedBox.shrink();
        final color = AppColors.forSource(op.sourceType);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                op.shortCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              op.name,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
