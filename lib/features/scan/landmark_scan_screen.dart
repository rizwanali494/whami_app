import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/landmark.dart';
import '../../data/models/region_pack.dart';
import '../../data/repositories/whami_repository.dart';

class LandmarkScanScreen extends StatefulWidget {
  final WhamiRepository repository;

  const LandmarkScanScreen({super.key, required this.repository});

  @override
  State<LandmarkScanScreen> createState() => _LandmarkScanScreenState();
}

class _LandmarkScanScreenState extends State<LandmarkScanScreen>
    with SingleTickerProviderStateMixin {
  // ── Match state ──────────────────────────────────────────────────────────
  Landmark? _matchedLandmark;
  int _matchPercent = 0;
  bool _isScanning = false;
  bool _saved = false;
  bool _usedAsAnchor = false;

  // ── Animation ────────────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Camera ───────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  bool _cameraInitializing = false;
  String _cameraStatus = 'Initializing camera...';
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  // ── Camera initialization with retry ────────────────────────────────────

  Future<void> _initCamera() async {
    if (_cameraInitializing || !mounted) return;

    if (mounted) {
      setState(() {
        _cameraInitializing = true;
        _cameraStatus = _retryCount == 0
            ? 'Initializing camera...'
            : 'Retrying camera (${_retryCount + 1}/$_maxRetries)...';
      });
    }

    // Dispose any existing controller first
    await _disposeCamera();

    try {
      // Step 1: enumerate cameras
      List<CameraDescription> cameras = [];
      try {
        cameras = await availableCameras();
      } catch (e) {
        throw Exception('Could not enumerate cameras: $e');
      }

      if (cameras.isEmpty) {
        throw Exception('No cameras found on this device');
      }

      // Step 2: prefer back camera, fall back to first available
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Step 3: initialize controller
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraInitialized = true;
        _cameraInitializing = false;
        _cameraStatus = 'Camera active';
        _retryCount = 0;
      });
    } catch (e) {
      if (!mounted) return;

      final errorMsg = _friendlyError(e.toString());

      if (_retryCount < _maxRetries - 1) {
        // Schedule a retry after a short delay
        _retryCount++;
        setState(() {
          _cameraInitializing = false;
          _cameraStatus = '$errorMsg — retrying...';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) await _initCamera();
      } else {
        setState(() {
          _cameraInitialized = false;
          _cameraInitializing = false;
          _cameraStatus = errorMsg;
        });
      }
    }
  }

  Future<void> _disposeCamera() async {
    final old = _cameraController;
    _cameraController = null;
    _cameraInitialized = false;
    try {
      await old?.dispose();
    } catch (_) {}
  }

  /// Converts raw exception text into a short user-readable message.
  String _friendlyError(String raw) {
    if (raw.contains('permission') || raw.contains('Permission')) {
      return 'Camera permission denied';
    }
    if (raw.contains('enumerate') || raw.contains('No cameras')) {
      return 'No camera found';
    }
    if (raw.contains('CameraException')) {
      // Extract just the code portion
      final match = RegExp(r'CameraException\(([^,)]+)').firstMatch(raw);
      if (match != null) return 'Camera error: ${match.group(1)}';
    }
    return 'Camera unavailable';
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _disposeCamera();
    super.dispose();
  }

  // ── Core scan logic — region-aware ───────────────────────────────────────

  /// Performs a simulated visual feature match scoped to the active region pack.
  /// If no pack is active, falls back to a generic result with low confidence.
  Future<void> _onScan() async {
    setState(() {
      _isScanning = true;
      _matchedLandmark = null;
      _matchPercent = 0;
      _saved = false;
      _usedAsAnchor = false;
    });

    // Simulate processing: frame capture + descriptor comparison
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final rand = Random();
    final activePackId = widget.repository.activePackId;
    final activePack = widget.repository.getRegionPackById(activePackId);

    Landmark bestLandmark;
    int matchPercent;

    if (activePack != null) {
      // ── Region-aware path ─────────────────────────────────────────────
      // Try using real loaded landmarks first (from GeoJSON in active pack)
      final loaded = widget.repository.getLandmarks();

      List<Landmark> candidates;
      if (loaded.isNotEmpty) {
        // Use actual pack landmarks
        candidates = loaded;
      } else {
        // Generate realistic simulated landmarks for this region
        candidates = _generateRegionLandmarks(activePack, rand);
      }

      // Sort by confidence desc, pick best
      candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
      final best = candidates.first;

      // Apply ±4% camera matching variance
      final rawMatch = best.confidence + (rand.nextDouble() * 0.08) - 0.04;
      matchPercent = (rawMatch.clamp(0.0, 1.0) * 100).round();
      bestLandmark = best;
    } else {
      // ── No active pack — low-confidence fallback ──────────────────────
      matchPercent = 45 + rand.nextInt(20); // 45–65%
      bestLandmark = Landmark(
        name: 'Unknown Feature',
        latitude: 0.0,
        longitude: 0.0,
        confidence: matchPercent / 100.0,
        saved: false,
        type: 'other',
      );
    }

    if (mounted) {
      setState(() {
        _matchedLandmark = bestLandmark;
        _matchPercent = matchPercent;
        _isScanning = false;
      });
    }
  }

  /// Generates realistic landmark candidates for a region pack based on its
  /// location and type. Uses the pack's trust score to calibrate confidence.
  List<Landmark> _generateRegionLandmarks(RegionPack pack, Random rand) {
    final types = _landmarkTypesForPack(pack.type);
    final names = _landmarkNamesForPack(pack);
    final baseConfidence = pack.trustScore / 100.0; // e.g. 0.87 for 87%

    return List.generate(names.length, (i) {
      final type = types[i % types.length];
      // Distribute landmarks around the pack's center with small offsets
      final coordEntry = _packCenterCoords(pack.id);
      final lat = coordEntry[0] + (rand.nextDouble() * 0.02 - 0.01);
      final lng = coordEntry[1] + (rand.nextDouble() * 0.02 - 0.01);
      final conf = (baseConfidence - 0.1 + rand.nextDouble() * 0.15).clamp(
        0.5,
        0.98,
      );

      return Landmark(
        name: names[i],
        latitude: lat,
        longitude: lng,
        confidence: conf,
        saved: false,
        type: type,
      );
    });
  }

  List<String> _landmarkTypesForPack(String packType) {
    switch (packType) {
      case 'Marine':
        return ['harbor', 'coastline', 'tower', 'bridge'];
      case 'Lake':
        return ['coastline', 'tower', 'building'];
      case 'Hiking':
        return ['mountain', 'tower', 'bridge'];
      case 'River':
        return ['bridge', 'coastline', 'building'];
      case 'Island':
        return ['coastline', 'harbor', 'mountain'];
      case 'Desert':
        return ['tower', 'mountain', 'building'];
      case 'Arctic':
        return ['coastline', 'mountain', 'tower'];
      case 'Urban':
        return ['building', 'bridge', 'tower'];
      default:
        return ['building', 'tower'];
    }
  }

  List<String> _landmarkNamesForPack(RegionPack pack) {
    final region = pack.name.replaceAll(' Pack', '').replaceAll(' Region', '');
    switch (pack.type) {
      case 'Marine':
        return [
          '$region Lighthouse',
          '$region Harbor Entrance',
          '$region Navigation Beacon',
          '$region Breakwater Tower',
        ];
      case 'Lake':
        return [
          '$region Marina Dock',
          '$region Observation Tower',
          '$region Shoreline Station',
        ];
      case 'Hiking':
        return [
          '$region Summit Cairn',
          '$region Trail Marker Peak',
          '$region Ridge Lookout',
          '$region Valley Waypoint',
        ];
      case 'River':
        return [
          '$region River Bridge',
          '$region Lock Station',
          '$region River Beacon',
        ];
      case 'Island':
        return [
          '$region Shore Cliff',
          '$region Island Lighthouse',
          '$region Reef Marker',
        ];
      case 'Desert':
        return [
          '$region Dune Ridge',
          '$region Desert Tower',
          '$region Rocky Outcrop',
        ];
      case 'Arctic':
        return [
          '$region Ice Station',
          '$region Polar Beacon',
          '$region Arctic Cliff',
        ];
      default:
        return ['$region Landmark A', '$region Landmark B'];
    }
  }

  List<double> _packCenterCoords(String packId) {
    const coords = <String, List<double>>{
      'sf_bay': [37.714, -122.308],
      'chesapeake': [38.228, -76.263],
      'gulf_mexico': [25.0, -90.0],
      'great_lakes': [45.0, -82.0],
      'tahoe': [39.089, -120.05],
      'mountain_view': [37.141, -121.997],
      'grand_canyon': [36.098, -112.096],
      'yellowstone': [44.4, -110.5],
      'new_york_harbor': [40.908, -73.465],
      'rotterdam': [51.904, 4.430],
      'english_channel': [50.0, -2.0],
      'north_sea': [56.0, 3.0],
      'mediterranean_west': [38.0, 5.0],
      'tokyo_bay': [35.47, 139.848],
      'sydney_harbour': [-33.865, 151.234],
      'great_barrier_reef': [-20.358, 148.952],
      'arctic_ocean': [85.0, 0.0],
      'antarctica': [-80.0, 0.0],
    };
    return coords[packId] ?? [0.0, 0.0];
  }

  void _onSave() => setState(() => _saved = true);

  void _onUseAsAnchor() {
    if (_matchedLandmark == null) return;
    widget.repository.setLandmarkAnchor(_matchedLandmark!, _matchPercent);
    setState(() => _usedAsAnchor = true);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _iconForType(String type) {
    switch (type) {
      case 'bridge':
        return Icons.cable;
      case 'tower':
        return Icons.cell_tower;
      case 'mountain':
        return Icons.landscape;
      case 'coastline':
        return Icons.waves;
      case 'harbor':
        return Icons.anchor;
      case 'island':
        return Icons.terrain;
      case 'building':
        return Icons.apartment;
      default:
        return Icons.place;
    }
  }

  Color _matchColor(int pct) {
    if (pct >= 85) return AppColors.trustHigh;
    if (pct >= 70) return AppColors.whami;
    return AppColors.magnetic;
  }

  String _uncertaintyLabel(int pct) {
    final meters = ((100 - pct) * 2).clamp(10, 120);
    return '±${meters}m';
  }

  bool get _hasMatch => _matchedLandmark != null && !_isScanning;
  bool get _packLoaded => widget.repository.activePackId.isNotEmpty;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activePack = widget.repository.getRegionPackById(
      widget.repository.activePackId,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Camera viewport ──────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: const Color(0xFF0D1520),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Live camera preview
                  if (_cameraInitialized && _cameraController != null)
                    Positioned.fill(child: CameraPreview(_cameraController!))
                  else
                    _CameraFallback(
                      status: _cameraStatus,
                      isInitializing: _cameraInitializing,
                      canRetry:
                          !_cameraInitializing && _retryCount >= _maxRetries,
                      onRetry: () {
                        _retryCount = 0;
                        _initCamera();
                      },
                    ),

                  // Scan reticle
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, _) {
                      final color = _hasMatch
                          ? _matchColor(_matchPercent)
                          : _isScanning
                          ? AppColors.whami.withValues(alpha: 0.5)
                          : AppColors.whami;
                      return Transform.scale(
                        scale: _hasMatch || _isScanning
                            ? 1.0
                            : _pulseAnim.value,
                        child: Container(
                          width: 220,
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: color, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              ..._buildCorners(color),
                              if (_isScanning)
                                const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.whami,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Status chips (bottom of viewport)
                  Positioned(
                    bottom: 16,
                    left: 12,
                    right: 12,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _Chip(
                          label: _cameraInitialized
                              ? 'Camera active'
                              : _cameraInitializing
                              ? 'Initializing...'
                              : 'Camera off',
                          color: _cameraInitialized
                              ? AppColors.trustHigh
                              : _cameraInitializing
                              ? AppColors.gps
                              : Colors.grey,
                          icon: _cameraInitialized
                              ? Icons.videocam
                              : Icons.videocam_off,
                        ),
                        if (!_packLoaded)
                          const _Chip(
                            label: 'No region active — activate a pack',
                            color: AppColors.magnetic,
                            icon: Icons.map_outlined,
                          ),
                        if (_packLoaded && !_hasMatch && !_isScanning)
                          _Chip(
                            label: activePack != null
                                ? 'Scanning: ${activePack.name}'
                                : 'Active region loaded',
                            color: Colors.white60,
                            icon: Icons.layers,
                          ),
                        if (_isScanning)
                          const _Chip(
                            label: 'Matching visual descriptors...',
                            color: AppColors.whami,
                            icon: Icons.search,
                          ),
                        if (_hasMatch) ...[
                          _Chip(
                            label: 'Match: $_matchPercent%',
                            color: _matchColor(_matchPercent),
                            icon: Icons.check_circle_outline,
                          ),
                          _Chip(
                            label: _matchedLandmark!.type.toUpperCase(),
                            color: AppColors.gps,
                            icon: _iconForType(_matchedLandmark!.type),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Top-right: mode badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'LANDMARK SCAN',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),

                  // Top-left: active region badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _PackBadge(activePack: activePack),
                  ),
                ],
              ),
            ),
          ),

          // ── Match result card ────────────────────────────────────────────
          if (_hasMatch)
            _MatchCard(
              landmark: _matchedLandmark!,
              matchPercent: _matchPercent,
              usedAsAnchor: _usedAsAnchor,
              matchColor: _matchColor(_matchPercent),
              iconForType: _iconForType,
              uncertaintyLabel: _uncertaintyLabel(_matchPercent),
              activePack: activePack,
            ),

          // ── No pack warning ──────────────────────────────────────────────
          if (!_packLoaded && !_hasMatch)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.alertWarningBorder.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.alertWarningBorder.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.alertWarningBorder,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No region pack is active. Activate a pack from the Region Packs screen to get accurate landmark matches for your area.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Action buttons ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: !_isScanning ? _onScan : null,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.document_scanner, size: 18),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan Landmark'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasMatch && !_saved ? _onSave : null,
                    icon: Icon(
                      _saved ? Icons.check : Icons.save,
                      size: 18,
                      color: _saved ? AppColors.trustHigh : null,
                    ),
                    label: Text(_saved ? 'Saved' : 'Save Match'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _saved
                          ? AppColors.trustHigh
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hasMatch && !_usedAsAnchor
                        ? _onUseAsAnchor
                        : null,
                    icon: Icon(
                      _usedAsAnchor ? Icons.anchor : Icons.add_location,
                      size: 18,
                      color: _usedAsAnchor ? AppColors.gps : null,
                    ),
                    label: Text(_usedAsAnchor ? 'Anchored' : 'Use as Anchor'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _usedAsAnchor
                          ? AppColors.gps
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCorners(Color color) {
    const double sz = 16;
    const double wt = 2.5;
    return [
      Positioned(
        top: 0,
        left: 0,
        child: _Corner(
          color: color,
          size: sz,
          weight: wt,
          top: true,
          left: true,
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: _Corner(
          color: color,
          size: sz,
          weight: wt,
          top: true,
          left: false,
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: _Corner(
          color: color,
          size: sz,
          weight: wt,
          top: false,
          left: true,
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: _Corner(
          color: color,
          size: sz,
          weight: wt,
          top: false,
          left: false,
        ),
      ),
    ];
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Shows camera loading / error state with an optional retry button.
class _CameraFallback extends StatelessWidget {
  final String status;
  final bool isInitializing;
  final bool canRetry;
  final VoidCallback onRetry;

  const _CameraFallback({
    required this.status,
    required this.isInitializing,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isInitializing)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.whami,
              ),
            )
          else
            const Icon(Icons.videocam_off, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(
            status,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          if (canRetry) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16, color: AppColors.whami),
              label: const Text(
                'Retry Camera',
                style: TextStyle(color: AppColors.whami, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.whami),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Top-left badge showing the active region pack name.
class _PackBadge extends StatelessWidget {
  final dynamic activePack; // RegionPack?

  const _PackBadge({this.activePack});

  @override
  Widget build(BuildContext context) {
    if (activePack == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: Colors.grey, size: 10),
            SizedBox(width: 4),
            Text(
              'NO REGION ACTIVE',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.trustHigh.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.offline_pin, color: AppColors.trustHigh, size: 10),
          const SizedBox(width: 4),
          Text(
            activePack.name.toUpperCase().replaceAll(' PACK', ''),
            style: const TextStyle(
              color: AppColors.trustHigh,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanded match result card.
class _MatchCard extends StatelessWidget {
  final Landmark landmark;
  final int matchPercent;
  final bool usedAsAnchor;
  final Color matchColor;
  final IconData Function(String) iconForType;
  final String uncertaintyLabel;
  final dynamic activePack;

  const _MatchCard({
    required this.landmark,
    required this.matchPercent,
    required this.usedAsAnchor,
    required this.matchColor,
    required this.iconForType,
    required this.uncertaintyLabel,
    required this.activePack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: matchColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: matchColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: matchColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconForType(landmark.type),
              color: matchColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        landmark.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: matchColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$matchPercent%',
                        style: TextStyle(
                          color: matchColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Lat ${landmark.latitude.toStringAsFixed(4)}, '
                  'Lng ${landmark.longitude.toStringAsFixed(4)}  ·  '
                  'Uncertainty: $uncertaintyLabel',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activePack != null
                      ? 'Matched against ${activePack.name} local dataset'
                      : 'Matched against fallback descriptor',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary.withValues(alpha: 0.55),
                  ),
                ),
                if (usedAsAnchor) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.trustHigh,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text(
                      '✓ USED AS POSITION ANCHOR',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final Color color;
  final double size;
  final double weight;
  final bool top;
  final bool left;

  const _Corner({
    required this.color,
    required this.size,
    required this.weight,
    required this.top,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          weight: weight,
          top: top,
          left: left,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double weight;
  final bool top;
  final bool left;

  _CornerPainter({
    required this.color,
    required this.weight,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = weight
      ..style = PaintingStyle.stroke;
    final h = left ? 0.0 : size.width;
    final v = top ? 0.0 : size.height;
    final hDir = left ? size.width : -size.width;
    final vDir = top ? size.height : -size.height;
    canvas.drawLine(Offset(h, v), Offset(h + hDir, v), paint);
    canvas.drawLine(Offset(h, v), Offset(h, v + vDir), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _Chip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
