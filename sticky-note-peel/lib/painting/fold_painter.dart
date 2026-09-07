import 'package:flutter/rendering.dart';

import '../helpers/fold_geometry.dart';

/// Draws the peeled corner over a note: the torn-away region in the screen
/// background, then the flap on top in the shaded note colour.
class FoldPainter extends CustomPainter {
  const FoldPainter({
    required this.dragX,
    required this.dragY,
    required this.background,
    required this.flapColor,
  });

  final double dragX;
  final double dragY;
  final Color background;
  final Color flapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = computeFoldGeometry(size.width, size.height, dragX, dragY);
    _fill(canvas, geometry.clipped, background);
    _fill(canvas, geometry.flap, flapColor);
  }

  void _fill(Canvas canvas, List<Offset> points, Color color) {
    if (points.length < 3) {
      return;
    }
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(FoldPainter oldDelegate) =>
      oldDelegate.dragX != dragX ||
      oldDelegate.dragY != dragY ||
      oldDelegate.background != background ||
      oldDelegate.flapColor != flapColor;
}
