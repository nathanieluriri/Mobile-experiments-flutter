import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// One radian every 650 ms, so a full turn takes this long.
final Duration _turn = Duration(
  microseconds: (650 * 2 * math.pi * 1000).round(),
);

/// A rotating open arc used while something is processing.
class LoadingRing extends StatefulWidget {
  const LoadingRing({
    super.key,
    required this.size,
    this.color = AppColors.accent,
    this.strokeWidth = 3,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  State<LoadingRing> createState() => _LoadingRingState();
}

class _LoadingRingState extends State<LoadingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _turn,
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _RingPainter(
            rotation: _clock.value * math.pi * 2,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.rotation,
    required this.color,
    required this.strokeWidth,
  });

  final double rotation;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.translate(-center.dx, -center.dy);
    final rect = Rect.fromLTWH(5, 5, size.width - 10, size.height - 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);
    canvas.drawArc(rect, 0, 265 * math.pi / 180, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
