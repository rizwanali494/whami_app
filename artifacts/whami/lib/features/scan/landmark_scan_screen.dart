import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';

class LandmarkScanScreen extends StatefulWidget {
  const LandmarkScanScreen({super.key});

  @override
  State<LandmarkScanScreen> createState() => _LandmarkScanScreenState();
}

class _LandmarkScanScreenState extends State<LandmarkScanScreen> with SingleTickerProviderStateMixin {
  bool _scanned = false;
  bool _saved = false;
  bool _usedAsAnchor = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Real Camera Controller
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraInitialized = false;
  String _cameraStatus = 'Initializing camera...';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras.first,
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
        if (mounted) {
          setState(() {
            _cameraStatus = 'No cameras found';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraStatus = 'Camera initialization failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onScan() {
    setState(() {
      _scanned = true;
      _saved = false;
      _usedAsAnchor = false;
    });
  }

  void _onSave() => setState(() => _saved = true);
  void _onUseAnchor() => setState(() => _usedAsAnchor = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        title: const Text(
          'Landmark Scan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Camera preview container
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: const Color(0xFF1A2A3A),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Real Camera View or loading placeholder
                  if (_cameraInitialized && _cameraController != null)
                    Center(
                      child: CameraPreview(_cameraController!),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.white24, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _cameraStatus,
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                  // Scan reticle
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, _) {
                      return Transform.scale(
                        scale: _scanned ? 1.0 : _pulseAnim.value,
                        child: Container(
                          width: 200,
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _scanned ? AppColors.trustHigh : AppColors.whami,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              ..._buildCorners(_scanned ? AppColors.trustHigh : AppColors.whami),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Status chips
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: _cameraInitialized ? 'Camera active' : 'Camera off',
                          color: _cameraInitialized ? AppColors.trustHigh : Colors.grey,
                          icon: Icons.videocam,
                        ),
                        _Chip(
                          label: _scanned ? 'Landmark match: 87%' : 'Scanning...',
                          color: _scanned ? AppColors.whami : Colors.grey,
                          icon: Icons.search,
                        ),
                        if (_scanned) ...[
                          _Chip(
                            label: 'Visual anchor quality: Good',
                            color: AppColors.trustHigh,
                            icon: Icons.anchor,
                          ),
                          _Chip(
                            label: 'Saved landmark: Harbor Tower',
                            color: AppColors.gps,
                            icon: Icons.location_on,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Mode label
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                ],
              ),
            ),
          ),

          // Scan result card
          if (_scanned)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.trustHigh.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.trustHigh.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.trustHigh, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Harbor Tower — 87% match',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Lat 37.8086, Lng -122.4100 · Uncertainty: ±35m',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (_usedAsAnchor)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.trustHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'ANCHOR',
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _onScan,
                    icon: const Icon(Icons.document_scanner, size: 18),
                    label: const Text('Scan Landmark'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanned ? _onSave : null,
                    icon: Icon(
                      _saved ? Icons.check : Icons.save,
                      size: 18,
                      color: _saved ? AppColors.trustHigh : null,
                    ),
                    label: Text(_saved ? 'Saved' : 'Save Landmark'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _saved ? AppColors.trustHigh : AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanned ? _onUseAnchor : null,
                    icon: Icon(
                      _usedAsAnchor ? Icons.anchor : Icons.add_location,
                      size: 18,
                      color: _usedAsAnchor ? AppColors.gps : null,
                    ),
                    label: Text(_usedAsAnchor ? 'Anchored' : 'Use as Anchor'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _usedAsAnchor ? AppColors.gps : AppColors.textPrimary,
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
      Positioned(top: 0, left: 0, child: _Corner(color: color, size: size, weight: weight, top: true, left: true)),
      Positioned(top: 0, right: 0, child: _Corner(color: color, size: size, weight: weight, top: true, left: false)),
      Positioned(bottom: 0, left: 0, child: _Corner(color: color, size: size, weight: weight, top: false, left: true)),
      Positioned(bottom: 0, right: 0, child: _Corner(color: color, size: size, weight: weight, top: false, left: false)),
    ];
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
        painter: _CornerPainter(color: color, weight: weight, top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double weight;
  final bool top;
  final bool left;

  _CornerPainter({required this.color, required this.weight, required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = weight..style = PaintingStyle.stroke;
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
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
