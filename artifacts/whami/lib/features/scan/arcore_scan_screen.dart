import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../core/constants/app_colors.dart';

class ArcoreScanScreen extends StatefulWidget {
  const ArcoreScanScreen({super.key});

  @override
  State<ArcoreScanScreen> createState() => _ArcoreScanScreenState();
}

class _ArcoreScanScreenState extends State<ArcoreScanScreen> with SingleTickerProviderStateMixin {
  bool _scanning = false;
  String _poseQuality = 'Medium';
  int _featurePoints = 128;
  int _visualMatch = 74;
  late AnimationController _gridAnim;

  // Real Camera Controller
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraInitialized = false;
  String _cameraStatus = 'Initializing camera...';

  @override
  void initState() {
    super.initState();
    _gridAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

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
    _gridAnim.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  void _onStartScan() {
    setState(() {
      _scanning = true;
      _poseQuality = 'Good';
      _featurePoints = 128 + (DateTime.now().millisecond % 80);
      _visualMatch = 74 + (DateTime.now().millisecond % 18);
    });
  }

  void _onReset() {
    setState(() {
      _scanning = false;
      _poseQuality = 'Medium';
      _featurePoints = 128;
      _visualMatch = 74;
    });
  }

  void _onSendToFusion() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.headerBg,
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.trustHigh, size: 16),
            const SizedBox(width: 8),
            Text(
              'AR pose sent to TrustFusionEngine — Visual match: $_visualMatch%',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _poseColor(String q) {
    switch (q) {
      case 'Good': return AppColors.trustHigh;
      case 'Medium': return AppColors.whami;
      default: return AppColors.magnetic;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        title: const Text(
          'ARCore Scan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Dark camera preview
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Colors.black,
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

                  // Animated AR grid overlay on top of camera
                  AnimatedBuilder(
                    animation: _gridAnim,
                    builder: (ctx, _) => CustomPaint(
                      painter: _ArGridPainter(
                        progress: _gridAnim.value,
                        active: _scanning,
                      ),
                    ),
                  ),

                  // Center reticle
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _scanning ? AppColors.trustHigh : Colors.white54,
                        width: 1.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _scanning ? Icons.my_location : Icons.radio_button_unchecked,
                      color: _scanning ? AppColors.trustHigh : Colors.white54,
                      size: 24,
                    ),
                  ),

                  // Mode tag
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        'ARCore Mode: Live',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),

                  // Stats overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      children: [
                        _ArStat(
                          label: 'Pose Quality',
                          value: _poseQuality,
                          color: _poseColor(_poseQuality),
                        ),
                        const SizedBox(height: 6),
                        _ArStat(
                          label: 'Feature Points',
                          value: '$_featurePoints',
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 6),
                        _ArStat(
                          label: 'Visual Match',
                          value: '$_visualMatch%',
                          color: AppColors.gps,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Info cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _InfoCard(
                  title: 'Pose Quality',
                  value: _poseQuality,
                  color: _poseColor(_poseQuality),
                  icon: Icons.device_hub,
                ),
                const SizedBox(width: 10),
                _InfoCard(
                  title: 'Feature Points',
                  value: '$_featurePoints',
                  color: Colors.white,
                  icon: Icons.scatter_plot,
                ),
                const SizedBox(width: 10),
                _InfoCard(
                  title: 'Visual Match',
                  value: '$_visualMatch%',
                  color: AppColors.gps,
                  icon: Icons.visibility,
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
                    onPressed: _onStartScan,
                    icon: Icon(
                      _scanning ? Icons.refresh : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(_scanning ? 'Rescan' : 'Start AR Scan'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _onReset,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reset Scan'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning ? _onSendToFusion : null,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Send to Fusion'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.gps,
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
}

class _ArStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ArStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.headerBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArGridPainter extends CustomPainter {
  final double progress;
  final bool active;

  _ArGridPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final baseAlpha = active ? 0.35 : 0.18;
    final paint = Paint()
      ..color = Color.fromRGBO(0, 200, 150, baseAlpha)
      ..strokeWidth = 0.8;

    const int lines = 12;
    final offset = progress * (size.height / lines);
    for (int i = -1; i <= lines + 1; i++) {
      final y = i * size.height / lines + offset;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    for (int i = 0; i <= 8; i++) {
      final x = i * size.width / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    if (active) {
      final bracketPaint = Paint()
        ..color = const Color(0xFF00FF99)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      const double bSize = 24;
      final cx = size.width / 2;
      final cy = size.height / 2;
      canvas.drawLine(Offset(cx - bSize, cy - bSize), Offset(cx - bSize + 10, cy - bSize), bracketPaint);
      canvas.drawLine(Offset(cx - bSize, cy - bSize), Offset(cx - bSize, cy - bSize + 10), bracketPaint);
      canvas.drawLine(Offset(cx + bSize, cy - bSize), Offset(cx + bSize - 10, cy - bSize), bracketPaint);
      canvas.drawLine(Offset(cx + bSize, cy - bSize), Offset(cx + bSize, cy - bSize + 10), bracketPaint);
    }
  }

  @override
  bool shouldRepaint(_ArGridPainter old) =>
      old.progress != progress || old.active != active;
}
