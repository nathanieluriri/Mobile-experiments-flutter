import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../constants/gooey_fab.dart' show kGooNeckWaist;
import '../theme/easings.dart';

/// How close together the circles along the thread are, so it holds across a
/// far jump rather than breaking into beads.
const kTabGooThreadPitch = 14.0;

/// The journey's stages, as shares of the whole.
///
/// The fill gathers into a blob at the old chip, the blob crosses the row
/// trailing a thread back to where it came from, a circle opens at the new
/// chip as the blob nears it, and the circle widens into the chip's pill.
/// The widening is finished before the chip's own fill takes over, so the
/// handover is between two shapes that already agree.
const kTabGooGatherEnd = 0.2;
const kTabGooTravelEnd = 0.7;
const kTabGooArriveStart = 0.55;
const kTabGooWidenEnd = 0.85;

/// The selected tab's fill on its way from one chip to the next.
///
/// A body that moves, not a fill that switches. Over a short hop the blob and
/// its thread read as a neck; over a long one the blob is plainly seen to
/// leave the old chip, cross the row, and arrive, which is what tells the
/// eye where the selection came from.
class TabGooPainter extends CustomPainter {
  const TabGooPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.colour,
    this.viscous = false,
  });

  /// The chip being left, in the strip's coordinates.
  final Rect from;

  /// The chip being arrived at.
  final Rect to;

  /// 0 at the old chip, 1 at the new.
  final double t;

  final Color colour;

  /// True for a journey through a document rather than a change of filter:
  /// every stage eases in and out, so the fill neither sets off nor stops at
  /// speed, and it moves like something thick.
  final bool viscous;

  static double _stage(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final radius = math.min(from.height, to.height) / 2;

    // The old fill gathers into a blob, then is gone: the blob is the fill.
    final gather = _stage(t, 0, kTabGooGatherEnd);
    if (gather < 1) {
      _pill(
        canvas,
        paint,
        from,
        ui.lerpDouble(
          from.width,
          from.height,
          viscous ? easeInOutCubic.transform(gather) : gather,
        )!,
      );
    }

    // The blob crosses.
    final travel = (viscous ? easeInOutCubic : easeInOutQuad).transform(
      _stage(t, kTabGooGatherEnd, kTabGooTravelEnd),
    );
    final blob = Offset.lerp(from.center, to.center, travel)!;
    canvas.drawCircle(blob, radius, paint);

    // The thread back to where it came from, thinning as it lengthens and
    // gone before the blob arrives.
    if (t > kTabGooGatherEnd && travel < 1) {
      _thread(canvas, paint, from.center, blob, radius, 1 - travel);
    }

    // The new chip opens to receive it, then widens into its own pill.
    final arrive = _eased(_stage(t, kTabGooArriveStart, kTabGooTravelEnd));
    final widen = _eased(_stage(t, kTabGooTravelEnd, kTabGooWidenEnd));
    if (arrive > 0) {
      if (widen > 0) {
        _pill(canvas, paint, to, ui.lerpDouble(to.height, to.width, widen)!);
      } else {
        canvas.drawCircle(to.center, radius * arrive, paint);
      }
    }
  }

  /// A stage as it is felt: as it runs for the desk's filters, and slowing
  /// into place for a viscous journey.
  double _eased(double share) =>
      viscous ? easeOutCubic.transform(share) : share;

  /// A chip's fill at [width], centred where the chip is.
  void _pill(Canvas canvas, Paint paint, Rect chip, double width) {
    if (width <= 0) return;
    final body = Rect.fromCenter(
      center: chip.center,
      width: width,
      height: chip.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(chip.height / 2)),
      paint,
    );
  }

  /// Circles from [tail] to [head], pinched at the waist, at [strength].
  void _thread(
    Canvas canvas,
    Paint paint,
    Offset tail,
    Offset head,
    double radius,
    double strength,
  ) {
    final span = head - tail;
    final count = math.max(2, (span.distance / kTabGooThreadPitch).ceil());
    for (var i = 1; i < count; i++) {
      final along = i / count;
      final waist = 1 - (1 - kGooNeckWaist) * math.sin(along * math.pi);
      final r = radius * waist * strength;
      if (r <= 0) continue;
      canvas.drawCircle(tail + span * along, r, paint);
    }
  }

  @override
  bool shouldRepaint(TabGooPainter oldDelegate) =>
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.t != t ||
      oldDelegate.colour != colour ||
      oldDelegate.viscous != viscous;
}
