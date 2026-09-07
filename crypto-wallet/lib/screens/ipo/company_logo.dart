import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';

/// A rounded gradient tile with the company's monogram.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    required this.size,
    required this.gradient,
    required this.monogram,
  });

  final double size;
  final GradientPair gradient;
  final String monogram;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(gradient: gradient, monogram: monogram),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.gradient, required this.monogram});

  final GradientPair gradient;
  final String monogram;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final radius = s * 0.3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(s, s), [gradient.$1, gradient.$2]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.06, s * 0.06, s * 0.88, s * 0.88),
        Radius.circular(radius * 0.82),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.white.withValues(alpha: 0.35),
    );
    final fontSize = s * 0.42;
    final painter = TextPainter(
      text: TextSpan(
        text: monogram,
        style: text(fontSize, weight: FontWeight.w700, color: AppColors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(
      canvas,
      Offset((s - painter.width) / 2, s / 2 + fontSize * 0.36 - baseline),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) =>
      oldDelegate.gradient != gradient || oldDelegate.monogram != monogram;
}
