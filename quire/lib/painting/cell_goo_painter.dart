import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../constants/gooey_fab.dart' show kGooNeckWaist;
import '../theme/easings.dart';

/// The journey's stages, as shares of the whole: the body gathers out of the
/// cell it is leaving, crosses to the new one on a thread, and opens into it.
const kCellGooGatherEnd = 0.18;
const kCellGooTravelEnd = 0.72;
const kCellGooArriveStart = 0.55;

/// How close together the circles along the thread are, so it holds over a
/// long jump instead of breaking into beads.
const kCellGooThreadPitch = 10.0;

/// The choice of cell, on its way from one cell to another.
///
/// The desk's tabs move along a row. A grid's choice moves anywhere, down and
/// across at once, so this carries the same body along a straight line between
/// the two cells' centres rather than along a row. It is drawn as circles and
/// meant to be blurred and cut at a threshold, which is what joins them into
/// one body with a neck rather than a string of dots.
class CellGooPainter extends CustomPainter {
  const CellGooPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.colour,
  });

  /// The cell being left and the cell being chosen, in the painter's space.
  final Rect from;
  final Rect to;

  /// 0 at the old cell, 1 at the new.
  final double t;

  final Color colour;

  static double _stage(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final radius = math.min(from.shortestSide, to.shortestSide) / 2;

    // The old cell's fill gathers into a body the size of a circle.
    final gather = _stage(t, 0, kCellGooGatherEnd);
    if (gather < 1) {
      final shrunk = Rect.lerp(
        from,
        Rect.fromCircle(center: from.center, radius: radius),
        easeOutCubic.transform(gather),
      )!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(shrunk, Radius.circular(radius)),
        paint,
      );
    }

    // The body crosses, trailing a thread back to where it came from that
    // thins as it goes and lets go before it arrives.
    final travel = easeInOutQuad.transform(
      _stage(t, kCellGooGatherEnd, kCellGooTravelEnd),
    );
    final head = Offset.lerp(from.center, to.center, travel)!;
    final crossing = t > kCellGooGatherEnd * 0.5 && t < kCellGooTravelEnd;
    if (crossing) {
      canvas.drawCircle(head, radius * 0.9, paint);
      final path = head - from.center;
      final length = path.distance;
      final left = 1 - _stage(t, kCellGooArriveStart, kCellGooTravelEnd);
      if (length > 0 && left > 0) {
        final steps = math.max(2, (length / kCellGooThreadPitch).ceil());
        for (var i = 1; i < steps; i++) {
          final along = i / steps;
          final waist =
              1 - (1 - kGooNeckWaist) * math.sin(along * math.pi);
          canvas.drawCircle(
            from.center + path * along,
            radius * 0.55 * waist * left,
            paint,
          );
        }
      }
    }

    // A circle opens at the new cell and widens into its shape.
    final arrive = _stage(t, kCellGooArriveStart, 1);
    if (arrive > 0) {
      final open = Rect.lerp(
        Rect.fromCircle(center: to.center, radius: radius * 0.9),
        to,
        easeOutCubic.transform(arrive),
      )!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          open,
          Radius.circular(ui.lerpDouble(radius, 4, arrive)!),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CellGooPainter old) =>
      old.from != from || old.to != to || old.t != t || old.colour != colour;
}
