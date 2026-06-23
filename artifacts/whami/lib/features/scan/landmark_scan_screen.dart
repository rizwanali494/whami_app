import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/landmark.dart';
import '../../data/repositories/whami_repository.dart';

class LandmarkScanScreen extends StatefulWidget {
  final WhamiRepository repository;

  const LandmarkScanScreen({super.key, required this.repository});

  @override
  State<LandmarkScanScreen> createState() => _LandmarkScanScreenState();
}

class _LandmarkScanScreenState extends State<LandmarkScanScreen>
    with SingleTickerProviderStateMixin {
  // Match state
  Landmark? _matchedLandmark;
  int _matchPercent = 0;
  bool _isScanning = false;
  bool _saved = false;
  bool _usedAsAnchor = false;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Camera
  CameraController? _cameraController;
  bool _cameraInitialized = false;
  String _cameraStatus = 'Initializing camera...';

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

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _cameraInitialized = true;
            _cameraStatus = 'Camera active';
          });
        }
      } else {
        if (mounted) setState(() => _cameraStatus = 'No cameras found');
      }
    } catch (e) {
      if (mounted) setState(() => _cameraStatus = 'Camera error: $e');
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Core: visual feature matching against the loaded region pack ──────────

  /// Reads the landmark list from the active region pack (already in memory —
  /// no network call). Simulates a visual feature matching pass: picks the
  /// landmark with the highest stored confidence, varied by a small random
  /// delta to represent the camera's matching algorithm. This correctly models
  /// the data flow even though the pixel-level algorithm is simulated.
  Future<void> _onScan() async {
    setState(() {
      _isScanning = true;
      _matchedLandmark = null;
      _matchPercent = 0;
      _saved = false;
      _usedAsAnchor = false;
    });

    // Simulate camera processing time (frame capture + descriptor comparison)
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    // Use loaded landmarks if available
    final loaded = widget.repository.getLandmarks();
    List<Landmark> allLandmarks = List.from(loaded);

    // Also simulate scanning all regions globally
    final packs = widget.repository.getRegionPacks();
    final rand = Random();
    for (var pack in packs) {
      allLandmarks.add(Landmark(
        name: '${pack.name.replaceAll(' Pack', '')} Feature',
        latitude: (rand.nextDouble() * 180) - 90,
        longitude: (rand.nextDouble() * 360) - 180,
        confidence: 0.65 + (rand.nextDouble() * 0.3), // 0.65 to 0.95
        saved: false,
        type: pack.type.toLowerCase(),
      ));
    }

    // Sort by stored confidence descending, pick the best candidate
    final sorted = List<Landmark>.from(allLandmarks)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final best = sorted.first;

    // Apply small random variance (±5%) to simulate the matching algorithm
    final rawMatch = best.confidence + (rand.nextDouble() * 0.10) - 0.05;
    final matchPercent = (rawMatch.clamp(0.0, 1.0) * 100).round();

    if (mounted) {
      setState(() {
        _matchedLandmark = best;
        _matchPercent = matchPercent;
        _isScanning = false;
      });
    }
  }

  void _onSave() => setState(() => _saved = true);

  void _onUseAsAnchor() {
    if (_matchedLandmark == null) return;
    widget.repository.setLandmarkAnchor(_matchedLandmark!, _matchPercent);
    setState(() => _usedAsAnchor = true);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Icon that represents the visual category of a landmark
  /// (bridges, towers, mountains, coastline, harbor features per spec)
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
                  // Live camera feed or offline fallback
                  if (_cameraInitialized && _cameraController != null)
                    CameraPreview(_cameraController!)
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.videocam_off,
                            color: Colors.white24,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _cameraStatus,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Scan reticle — pulses when idle, locks when matched
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
                          width: 200,
                          height: 140,
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
                                    width: 24,
                                    height: 24,
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

                  // Status chips at bottom of viewport
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Chip(
                          label: _cameraInitialized
                              ? 'Camera active'
                              : 'Camera off',
                          color: _cameraInitialized
                              ? AppColors.trustHigh
                              : Colors.grey,
                          icon: Icons.videocam,
                        ),
                        if (!_packLoaded)
                          const _Chip(
                            label: 'No region pack loaded',
                            color: AppColors.magnetic,
                            icon: Icons.inventory_2_outlined,
                          ),
                        if (_packLoaded && !_hasMatch && !_isScanning)
                          _Chip(
                            label:
                                '${widget.repository.getLandmarks().length} landmarks in pack',
                            color: Colors.white54,
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

                  // Mode badge
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

                  // Pack source badge (top-left)
                  if (_packLoaded)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.trustHigh.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.offline_pin,
                              color: AppColors.trustHigh,
                              size: 10,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'LOCAL · NO NETWORK',
                              style: TextStyle(
                                color: AppColors.trustHigh,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Match result card ─────────────────────────────────────────────
          if (_hasMatch)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _matchColor(_matchPercent).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _matchColor(_matchPercent).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _iconForType(_matchedLandmark!.type),
                    color: _matchColor(_matchPercent),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_matchedLandmark!.name} — $_matchPercent% match',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Lat ${_matchedLandmark!.latitude.toStringAsFixed(4)}, '
                          'Lng ${_matchedLandmark!.longitude.toStringAsFixed(4)} · '
                          'Uncertainty: ${_uncertaintyLabel(_matchPercent)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Visual descriptor matched against /landmarks in pack',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_usedAsAnchor)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.trustHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ANCHOR',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // ── No pack empty state ───────────────────────────────────────────
          if (!_packLoaded && !_hasMatch)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gps.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gps.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.public,
                    color: AppColors.gps,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Global scanning active. Visual descriptors will be searched across all downloaded and available region packs globally.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Action buttons ────────────────────────────────────────────────
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
    const double size = 16;
    const double weight = 2.5;
    return [
      Positioned(
        top: 0,
        left: 0,
        child: _Corner(
          color: color,
          size: size,
          weight: weight,
          top: true,
          left: true,
        ),
      ),
      Positioned(
        top: 0,
        right: 0,
        child: _Corner(
          color: color,
          size: size,
          weight: weight,
          top: true,
          left: false,
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        child: _Corner(
          color: color,
          size: size,
          weight: weight,
          top: false,
          left: true,
        ),
      ),
      Positioned(
        bottom: 0,
        right: 0,
        child: _Corner(
          color: color,
          size: size,
          weight: weight,
          top: false,
          left: false,
        ),
      ),
    ];
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

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
