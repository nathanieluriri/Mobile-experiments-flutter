import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/rendering.dart';

/// The smallest and largest the travelling body is across. Never a speck
/// because it set off from one, and never a balloon because a row happens to
/// be tall.
const kCellGooBodyMin = 20.0;
const kCellGooBodyMax = 28.0;

/// The corner a cell's own fill has, which the body gives up as it gathers
/// and takes back as it spreads.
const kCellGooCellCorner = 4.0;

/// How much goo the neck between the body and what it left behind holds.
/// Stretched longer it gets thinner, the way a thread of honey does.
const kCellGooNeckVolume = 520.0;

/// The thinnest the neck goes. Blurred and cut at the threshold, a neck much
/// thinner than this vanishes in the middle and leaves two pieces, and goo
/// that comes apart and pops out of sight is not goo.
const kCellGooNeckMin = 6.5;

/// How fast the body has to be going to be drawn out as far as it goes, and
/// how far that is.
const kCellGooStretchAt = 900.0;
const kCellGooStretch = 0.45;
const kCellGooPinch = 0.22;

/// The choice of cell as goo at one moment: the body, what it trails, and
/// how fast it is going.
@immutable
class CellGoo {
  const CellGoo({
    required this.body,
    required this.corner,
    this.tail = Offset.zero,
    this.tailRadius = 0,
    this.neck = 0,
    this.velocity = Offset.zero,
  });

  /// The body: a cell's fill, a drop, or anything between the two.
  final Rect body;
  final double corner;

  /// What the body left behind, and the neck joining the two. No neck at all
  /// once the two are one.
  final Offset tail;
  final double tailRadius;
  final double neck;

  /// How fast the body is moving, which is how far it is drawn out.
  final Offset velocity;

  CellGoo shift(Offset by) => CellGoo(
    body: body.shift(by),
    corner: corner,
    tail: tail + by,
    tailRadius: tailRadius,
    neck: neck,
    velocity: velocity,
  );

  @override
  bool operator ==(Object other) =>
      other is CellGoo &&
      other.body == body &&
      other.corner == corner &&
      other.tail == tail &&
      other.tailRadius == tailRadius &&
      other.neck == neck &&
      other.velocity == velocity;

  @override
  int get hashCode =>
      Object.hash(body, corner, tail, tailRadius, neck, velocity);
}

/// The choice of cell, as goo.
///
/// Drawn as plain shapes, a body, a neck and what the neck trails back to,
/// and meant to be blurred and cut at a threshold, which is what joins them
/// into one body with a neck rather than three shapes touching.
class CellGooPainter extends CustomPainter {
  const CellGooPainter({required this.goo, required this.colour});

  final CellGoo goo;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final body = goo.body;
    if (goo.neck > 0 && goo.tailRadius > 0) {
      canvas
        ..drawLine(
          goo.tail,
          body.center,
          Paint()
            ..color = colour
            ..strokeWidth = goo.neck * 2
            ..strokeCap = StrokeCap.round,
        )
        ..drawCircle(goo.tail, goo.tailRadius, paint);
    }
    if (body.width <= 0 || body.height <= 0) return;

    // While it is a drop it is drawn out along the way it is going and
    // pinched across it. Spread into a cell it is not, so the stretch goes as
    // the drop widens, and there is no moment where it is one and then the
    // other.
    final longest = math.max(body.width, body.height);
    final roundness = (1 - (body.width - body.height).abs() / (0.5 * longest))
        .clamp(0.0, 1.0);
    final speed = goo.velocity.distance;
    var width = body.width;
    var height = body.height;
    if (roundness > 0 && speed > 0) {
      final stretch = (speed / kCellGooStretchAt).clamp(0.0, 1.0) * roundness;
      final along = Offset(
        (goo.velocity.dx / speed).abs(),
        (goo.velocity.dy / speed).abs(),
      );
      width *=
          1 + stretch * (kCellGooStretch * along.dx - kCellGooPinch * along.dy);
      height *=
          1 + stretch * (kCellGooStretch * along.dy - kCellGooPinch * along.dx);
    }
    final drawn = Rect.fromCenter(
      center: body.center,
      width: width,
      height: height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        drawn,
        Radius.circular(math.min(goo.corner, drawn.shortestSide / 2)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(CellGooPainter old) =>
      old.goo != goo || old.colour != colour;
}
