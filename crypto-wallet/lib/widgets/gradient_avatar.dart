import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/theme.dart';

/// A round gradient with the recipient's initial.
class GradientAvatar extends StatelessWidget {
  const GradientAvatar({
    super.key,
    required this.size,
    required this.gradient,
    required this.label,
  });

  final double size;
  final GradientPair gradient;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AvatarPainter(
        gradient: gradient,
        initial: label.isEmpty ? '' : label[0].toUpperCase(),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter({required this.gradient, required this.initial});

  final GradientPair gradient;
  final String initial;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(s, s), [
        gradient.$1,
        gradient.$2,
      ]);
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, paint);

    final fontSize = s * 0.38;
    final painter = TextPainter(
      text: TextSpan(
        text: initial,
        style: text(fontSize, weight: FontWeight.w600, color: AppColors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.paint(
      canvas,
      Offset((s - painter.width) / 2, s / 2 + fontSize * 0.36 - baseline),
    );
  }

  @override
  bool shouldRepaint(_AvatarPainter oldDelegate) =>
      oldDelegate.gradient != gradient || oldDelegate.initial != initial;
}
