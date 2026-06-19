import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/models/position_opinion.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/whami_mock_repository.dart';
import '../../../data/mock/region_pack_cdn.dart';

class WhamiMapView extends StatefulWidget {
  final List<PositionOpinion> opinions;
  final Map<String, bool> layerVisibility;
  final WhamiMockRepository repository;

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
  List<Polyline> _seamapLines = [];
  List<CircleMarker> _magneticPoints = [];
  List<CircleMarker> _landmarkDots = [];
  bool _packLoaded = false;

  late final MapController _mapController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _loadRegionPack();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// Simulates reading GeoJSON from local storage (file:// in native build).
  /// On web this reads from Flutter assets — same code path, different source.
  Future<void> _loadRegionPack() async {
    try {
      final seamapRaw = await rootBundle.loadString(
        'assets/region_packs/sf_bay/seamap.geojson',
      );
      final landmarkRaw = await rootBundle.loadString(
        'assets/region_packs/sf_bay/landmarks.geojson',
      );
      final magneticRaw = await rootBundle.loadString(
        'assets/region_packs/sf_bay/magnetic.geojson',
      );

      final seamap = jsonDecode(seamapRaw) as Map<String, dynamic>;
      final landmarks = jsonDecode(landmarkRaw) as Map<String, dynamic>;
      final magnetic = jsonDecode(magneticRaw) as Map<String, dynamic>;

      setState(() {
        _seamapLines = _parseSeamapLines(seamap);
        _landmarkDots = _parseLandmarkDots(landmarks);
        _magneticPoints = _parseMagneticGrid(magnetic);
        _packLoaded = true;
      });
    } catch (e) {
      debugPrint('WHAMI: region pack load error: $e');
    }
  }

  // ── GeoJSON parsers ───────────────────────────────────────────────────────

  List<Polyline> _parseSeamapLines(Map<String, dynamic> geojson) {
    final lines = <Polyline>[];
    for (final f in geojson['features'] as List) {
      final geom = f['geometry'] as Map<String, dynamic>;
      if (geom['type'] != 'LineString') continue;
      final coords = (geom['coordinates'] as List)
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();
      lines.add(
        Polyline(
          points: coords,
          color: const Color(0xFF1A6B9E),
          strokeWidth: 1.8,
          pattern: StrokePattern.dashed(segments: const [8, 4]),
        ),
      );
    }
    return lines;
  }

  List<CircleMarker> _parseLandmarkDots(Map<String, dynamic> geojson) {
    final dots = <CircleMarker>[];
    for (final f in geojson['features'] as List) {
      final geom = f['geometry'] as Map<String, dynamic>;
      if (geom['type'] != 'Point') continue;
      final coords = geom['coordinates'] as List;
      final saved = f['properties']['saved'] as bool? ?? false;
      dots.add(
        CircleMarker(
          point: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
          radius: saved ? 7 : 5,
          color: saved
              ? Colors.white.withOpacity(0.85)
              : Colors.white.withOpacity(0.4),
          borderColor: Colors.white.withOpacity(0.6),
          borderStrokeWidth: 1.2,
        ),
      );
    }
    return dots;
  }

  List<CircleMarker> _parseMagneticGrid(Map<String, dynamic> geojson) {
    final points = <CircleMarker>[];
    for (final f in geojson['features'] as List) {
      final geom = f['geometry'] as Map<String, dynamic>;
      if (geom['type'] != 'Point') continue;
      final coords = geom['coordinates'] as List;
      final stability = (f['properties']['stability'] as num).toDouble();
      final color = Color.lerp(
        const Color(0xFFE24B4A),
        const Color(0xFF27AE60),
        (stability - 0.80) / 0.20,
      )!;
      points.add(
        CircleMarker(
          point: LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          ),
          radius: 4,
          color: color.withOpacity(0.55),
          borderStrokeWidth: 0,
        ),
      );
    }
    return points;
  }

  // ── Opinion layers ────────────────────────────────────────────────────────

  List<CircleMarker> _buildUncertaintyRings(List<PositionOpinion> opinions) {
    final rings = <CircleMarker>[];
    for (final op in opinions) {
      if (op.confidence == 0 || op.uncertaintyRadius <= 0 || !op.isActive) {
        continue;
      }
      final color = _colorForSource(op.sourceType);
      rings.add(
        CircleMarker(
          point: LatLng(op.latitude, op.longitude),
          radius: op.uncertaintyRadius,
          useRadiusInMeter: true,
          color: color.withOpacity(0.09),
          borderColor: color.withOpacity(0.40),
          borderStrokeWidth: 1.2,
        ),
      );
    }
    return rings;
  }

  List<CircleMarker> _buildOpinionDots(List<PositionOpinion> opinions) {
    final dots = <CircleMarker>[];
    for (final op in opinions) {
      if (op.confidence == 0) continue;
      final color = _colorForSource(op.sourceType);

      if (op.sourceType == 'whami' && widget.repository.isTracking) {
        // Pulsing glow for the verified WHAMI position when tracking
        dots.add(
          CircleMarker(
            point: LatLng(op.latitude, op.longitude),
            radius: 12 + (_pulseController.value * 8),
            color: color.withOpacity(
              0.35 * (1.0 - _pulseController.value * 0.4),
            ),
            borderStrokeWidth: 0,
          ),
        );
      } else {
        dots.add(
          CircleMarker(
            point: LatLng(op.latitude, op.longitude),
            radius: 14,
            color: color.withOpacity(0.18),
            borderStrokeWidth: 0,
          ),
        );
      }
    }
    return dots;
  }

  List<Marker> _buildOpinionMarkers(List<PositionOpinion> opinions) {
    final markers = <Marker>[];
    for (final op in opinions) {
      if (op.confidence == 0) continue;
      final color = _colorForSource(op.sourceType);
      markers.add(
        Marker(
          point: LatLng(op.latitude, op.longitude),
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              op.shortCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Polyline> _buildNearestLandmarkLine() {
    final whamiPos = widget.repository.getTrustedPosition();
    if (whamiPos.confidence == 0) return [];

    final nearest = widget.repository.findNearestLandmark(
      whamiPos.latitude,
      whamiPos.longitude,
    );
    if (nearest == null) return [];

    return [
      Polyline(
        points: [
          LatLng(whamiPos.latitude, whamiPos.longitude),
          LatLng(nearest.latitude, nearest.longitude),
        ],
        color: AppColors.whami.withOpacity(0.6),
        strokeWidth: 1.5,
        pattern: StrokePattern.dashed(segments: const [6, 4]),
      ),
    ];
  }

  List<Polyline> _buildBreadcrumbsTrail() {
    final trailData = widget.repository.trail;
    if (trailData.isEmpty) return [];

    final points = trailData
        .map(
          (pt) => LatLng(pt['latitude'] as double, pt['longitude'] as double),
        )
        .toList();

    return [
      Polyline(
        points: points,
        color: AppColors.whami.withOpacity(0.7),
        strokeWidth: 2.2,
        pattern: StrokePattern.dashed(segments: const [4, 4]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final opinions = widget.opinions;

    // React to map centering commands from the repository
    if (widget.repository.mapCenterLat != null &&
        widget.repository.mapCenterLng != null) {
      final targetLat = widget.repository.mapCenterLat!;
      final targetLng = widget.repository.mapCenterLng!;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(LatLng(targetLat, targetLng), 14.5);
          widget.repository.mapCenterLat = null;
          widget.repository.mapCenterLng = null;
        }
      });
    } else if (widget.repository.isTracking) {
      // Auto-follow center when live tracking
      final whamiPos = widget.repository.getTrustedPosition();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(
            LatLng(whamiPos.latitude, whamiPos.longitude),
            _mapController.camera.zoom,
          );
        }
      });
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(
                  (RegionPackCdn.centers[widget.repository.activePackId] ?? RegionPackCdn.centers['sf_bay']!).$1,
                  (RegionPackCdn.centers[widget.repository.activePackId] ?? RegionPackCdn.centers['sf_bay']!).$2,
                ),
                initialZoom: 12.5,
                minZoom: 8,
                maxZoom: 18,
                backgroundColor: const Color(0xFF1a2332),
              ),
              children: [
                // ── Background tiles (CARTO dark — offline toggleable base layer) ──
                if (widget.layerVisibility['mapTiles'] == true)
                  TileLayer(
                    urlTemplate:
                        'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}@2x.png',
                    userAgentPackageName: 'global.whami.app',
                    maxZoom: 19,
                    fallbackUrl:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),

                // ── Region pack layer 1: Seamap / chart lines ──
                if (_packLoaded && widget.layerVisibility['seamap'] == true)
                  PolylineLayer(polylines: _seamapLines),

                // ── Region pack layer 2: Magnetic field grid ──
                if (_packLoaded && widget.layerVisibility['magnetic'] == true)
                  CircleLayer(circles: _magneticPoints),

                // ── Region pack layer 3: Landmark dots ──
                if (_packLoaded && widget.layerVisibility['landmarks'] == true)
                  CircleLayer(circles: _landmarkDots),

                // ── Nearest landmark indicator line ──
                if (_packLoaded &&
                    widget.layerVisibility['landmarks'] == true &&
                    widget.layerVisibility['opinions'] == true)
                  PolylineLayer(polylines: _buildNearestLandmarkLine()),

                // ── Trail / breadcrumbs layer ──
                if (widget.layerVisibility['opinions'] == true)
                  PolylineLayer(polylines: _buildBreadcrumbsTrail()),

                // ── Position opinion layers ──
                if (widget.layerVisibility['uncertainty'] == true)
                  CircleLayer(circles: _buildUncertaintyRings(opinions)),

                if (widget.layerVisibility['opinions'] == true) ...[
                  CircleLayer(circles: _buildOpinionDots(opinions)),
                  MarkerLayer(markers: _buildOpinionMarkers(opinions)),
                ],
              ],
            ),

            // ── Offline status label overlay ──
            if (_packLoaded)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0D1117),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.layers,
                        size: 10,
                        color: Color(0xFF4CAF50),
                      ),
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
      },
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

// ── Map legend row ────────────────────────────────────────────────────────────

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
