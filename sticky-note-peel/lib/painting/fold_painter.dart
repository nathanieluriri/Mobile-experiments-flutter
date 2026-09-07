import 'package:flutter/rendering.dart';

import '../helpers/fold_geometry.dart';

/// Draws the peeled corner over a note: the torn-away region in the screen
/// background, then the flap on top in the shaded note colour.
class FoldPainter extends CustomPainter {
  const FoldPainter({
    required double this.dragX,
    required double this.dragY,
    required this.background,
    required this.flapColor,
  }) : restInset = 0;

  /// A corner turned down by [restInset] and left there, for anything that
  /// wants the folded look without a finger on it.
  const FoldPainter.atRest({
    required this.restInset,
    required this.background,
    required this.flapColor,
  })  : dragX = null,
        dragY = null;

  /// Where the corner has been pulled to, or null to sit at [restInset].
  final double? dragX;
  final double? dragY;

  /// How far in from the corner an untouched fold sits.
  final double restInset;

  final Color background;
  final Color flapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = computeFoldGeometry(
      size.width,
      size.height,
      dragX ?? size.width - restInset,
      dragY ?? restInset,
    );
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
      oldDelegate.restInset != restInset ||
      oldDelegate.background != background ||
      oldDelegate.flapColor != flapColor;
}
