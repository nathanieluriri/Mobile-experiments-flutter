import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Casts a blurred shadow of [shape] that is clipped away inside the shape
/// itself, so a translucent fill drawn on top stays the colour it was given
/// instead of being darkened from below.
class OuterShadowPainter extends CustomPainter {
  const OuterShadowPainter({
    required this.shape,
    required this.color,
    required this.sigma,
    required this.offset,
  });

  final OutlinedBorder shape;
  final Color color;

  /// Standard deviation of the blur, which is half a CSS blur radius.
  final double sigma;

  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final path = shape.getOuterPath(bounds);
    final reach = bounds.inflate(sigma * 4 + offset.distance + 1);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(reach),
      path,
    );
    canvas
      ..save()
      ..clipPath(outside)
      ..drawPath(
        path.shift(offset),
        Paint()
          ..color = color
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, sigma),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(OuterShadowPainter old) =>
      old.shape != shape ||
      old.color != color ||
      old.sigma != sigma ||
      old.offset != offset;
}
