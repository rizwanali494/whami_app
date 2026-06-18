import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) context.go('/map');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.headerBg,
      body: Stack(
        children: [
          // Background grid
          CustomPaint(
            painter: _GridPainter(),
            child: Container(),
          ),
          // Center content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo animation
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        children: [
                          // W icon mark
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.whami, width: 2.5),
                              color: AppColors.whami.withOpacity(0.12),
                            ),
                            child: const Center(
                              child: Text(
                                'W',
                                style: TextStyle(
                                  color: AppColors.whami,
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // WHAMI text
                          const Text(
                            'WHAMI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'WHERE AM I?',
                            style: TextStyle(
                              color: Color(0xFF546E7A),
                              fontSize: 11,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Tagline
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => FadeTransition(
                    opacity: _taglineFade,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: AppColors.whami.withOpacity(0.4)),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Text(
                        'Verified by the real world.',
                        style: TextStyle(
                          color: AppColors.whami,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom loading indicator
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => FadeTransition(
                opacity: _taglineFade,
                child: Column(
                  children: [
                    SizedBox(
                      width: 120,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.whami),
                        minHeight: 2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Initializing fusion engine...',
                      style: TextStyle(
                        color: Color(0xFF546E7A),
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Source legend dots
          Positioned(
            bottom: 30,
            right: 24,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) => FadeTransition(
                opacity: _taglineFade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    _SourceDot(color: AppColors.whami, label: 'WHAMI'),
                    _SourceDot(color: AppColors.gps, label: 'GPS'),
                    _SourceDot(color: AppColors.landmark, label: 'Landmark'),
                    _SourceDot(color: AppColors.magnetic, label: 'Magnetic'),
                    _SourceDot(color: AppColors.sextant, label: 'Sky'),
                    _SourceDot(color: AppColors.imu, label: 'IMU'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceDot extends StatelessWidget {
  final Color color;
  final String label;

  const _SourceDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.6), fontSize: 9),
          ),
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;
    const int lines = 16;
    for (int i = 0; i <= lines; i++) {
      final x = size.width * i / lines;
      final y = size.height * i / lines;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
