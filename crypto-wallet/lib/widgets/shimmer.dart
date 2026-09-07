import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

const Duration _sweep = Duration(milliseconds: 1300);

/// A rounded placeholder with a highlight sweeping across it.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _sweep,
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
          size: Size(widget.width, widget.height),
          painter: _ShimmerPainter(t: _clock.value, radius: widget.radius),
        );
      },
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.t, required this.radius});

  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(-size.width + t * size.width * 2.4, 0);
    final end = Offset(start.dx + size.width, size.height * 0.6);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        start,
        end,
        const [
          AppColors.shimmerBase,
          AppColors.shimmerHighlight,
          AppColors.shimmerBase,
        ],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ShimmerPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.radius != radius;
}
