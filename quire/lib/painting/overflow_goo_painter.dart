import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// The single body the overflow menu oozes out of the dots as.
///
/// One shape, not two: it starts as a blob the size of the three dots and
/// grows into the panel's own rectangle, so the menu reads as having been
/// pulled out of the thing that opened it rather than having appeared over it.
/// The blur and threshold above keep every stage of that in between shape
/// rounded, which is what makes it goo rather than a rectangle inflating.
class OverflowGooPainter extends CustomPainter {
  const OverflowGooPainter({
    required this.from,
    required this.to,
    required this.fromRadius,
    required this.toRadius,
    required this.t,
    required this.colour,
  });

  /// The dots, in the coordinates of the layer this paints into.
  final Rect from;

  /// The panel, in the same coordinates.
  final Rect to;

  final double fromRadius;
  final double toRadius;

  /// 0 as the body leaves the dots, 1 as it arrives at the panel.
  final double t;

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.lerp(from, to, t);
    if (body == null || body.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body,
        Radius.circular(ui.lerpDouble(fromRadius, toRadius, t)!),
      ),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(OverflowGooPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.fromRadius != fromRadius ||
      oldDelegate.toRadius != toRadius ||
      oldDelegate.t != t ||
      oldDelegate.colour != colour;
}
