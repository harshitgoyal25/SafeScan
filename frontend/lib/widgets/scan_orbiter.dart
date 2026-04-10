import 'package:flutter/material.dart';
import 'dart:math' as math;

class ScanOrbiter extends StatefulWidget {
  final double progress;
  final bool isScanning;

  const ScanOrbiter({
    super.key,
    required this.progress,
    required this.isScanning,
  });

  @override
  State<ScanOrbiter> createState() => _ScanOrbiterState();
}

class _ScanOrbiterState extends State<ScanOrbiter>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isScanning) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(ScanOrbiter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isScanning && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // RING 1
        RotationTransition(
          turns: _rotationController,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
        ),

        // ORBITAL DOTS
        AnimatedBuilder(
          animation: _rotationController,
          builder: (context, child) {
            return CustomPaint(
              size: const Size(260, 260),
              painter: _OrbitalPainter(
                angle: _rotationController.value * 2 * math.pi,
                progress: widget.progress,
              ),
            );
          },
        ),

        // CENTER STATUS
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "${(widget.progress * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
            const Text(
              "ANALYZING FEATURES",
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrbitalPainter extends CustomPainter {
  final double angle;
  final double progress;

  _OrbitalPainter({required this.angle, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw partial arc based on progress
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );

    // Draw orbiting glow dot
    final dotPos = Offset(
      center.dx + radius * math.cos(angle - math.pi / 2),
      center.dy + radius * math.sin(angle - math.pi / 2),
    );

    final dotPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(dotPos, 8, dotPaint);
    canvas.drawCircle(dotPos, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OrbitalPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.progress != progress;
}
