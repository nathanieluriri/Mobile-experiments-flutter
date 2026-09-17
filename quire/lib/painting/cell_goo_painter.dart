import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../constants/gooey_fab.dart' show kGooNeckWaist;
import '../theme/easings.dart';

/// A move's stages, as shares of the whole: the body gathers out of the cell
/// it is leaving, crosses to the new one on a thread, and opens into it.
const kCellGooGatherEnd = 0.18;
const kCellGooTravelEnd = 0.72;
const kCellGooArriveStart = 0.55;

/// A first choice: a drop condenses at the middle of the cell, then spreads
/// out to its edges.
const kCellGooCondenseEnd = 0.32;

/// A choice let go: the cell draws in to a drop, and the drop dries up.
const kCellGooDrawInEnd = 0.5;

/// How far the travelling body is drawn out along its way, and pinched
/// across it, at the middle of the journey.
const kCellGooStretch = 0.7;
const kCellGooPinch = 0.28;

/// The smallest and largest the body is across. Never a speck because it set
/// off from one, and never a balloon because a row happens to be tall.
const kCellGooBodyMin = 20.0;
const kCellGooBodyMax = 28.0;

/// How close together the circles along the thread are, so it holds over a
/// long jump instead of breaking into beads.
const kCellGooThreadPitch = 10.0;

/// The corner a cell's own fill has, which the body gives up as it gathers
/// and takes back as it opens.
const kCellGooCellCorner = 4.0;

/// The body at one moment: the rectangle it fills and how round its corners
/// are.
typedef CellGooShape = ({Rect rect, double corner});

/// The choice of cell, as goo.
///
/// The desk's tabs move along a row. A grid's choice moves anywhere, down and
/// across at once, so this carries the same body along a straight line between
/// the two cells' centres. With both cells it is a move. With only [to] it is
/// a first choice, which condenses out of nothing, and with only [from] it is
/// a choice let go, which dries up where it was. It is drawn as circles and
/// meant to be blurred and cut at a threshold, which is what joins them into
/// one body with a neck rather than a string of dots.
class CellGooPainter extends CustomPainter {
  const CellGooPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.colour,
    this.fromCorner = kCellGooCellCorner,
  });

  /// Where the body set off from, and the cell it is going to, in the
  /// painter's space.
  final Rect? from;
  final Rect? to;

  /// How round [from] was when the body set off: a cell's corner when it
  /// left a cell at rest, or rounder when it was already on its way somewhere.
  final double fromCorner;

  /// 0 as it sets off, 1 once it is home.
  final double t;

  final Color colour;

  static double _stage(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  static double _radiusFor(Rect? from, Rect? to) {
    final sides = <double>[
      if (from != null) math.max(0.0, from.shortestSide),
      if (to != null) math.max(0.0, to.shortestSide),
    ];
    if (sides.isEmpty) return 0;
    final smallest = sides.reduce(math.min);
    final floor = math.min(kCellGooBodyMin, sides.reduce(math.max));
    return smallest.clamp(floor, kCellGooBodyMax) / 2;
  }

  /// [cell] drawn in towards a circle of [radius], [share] of the way, its
  /// corners rounding from [corner] as it goes.
  static CellGooShape _gathered(
    Rect cell,
    double corner,
    double radius,
    double share,
  ) => (
    rect: Rect.lerp(
      cell,
      Rect.fromCircle(center: cell.center, radius: radius),
      share,
    )!,
    corner: ui.lerpDouble(corner, radius, share)!,
  );

  /// A circle opening out to fill [cell], [share] of the way.
  static CellGooShape _opened(Rect cell, double radius, double share) => (
    rect: Rect.lerp(
      Rect.fromCircle(center: cell.center, radius: radius * 0.9),
      cell,
      share,
    )!,
    corner: ui.lerpDouble(radius * 0.9, kCellGooCellCorner, share)!,
  );

  static CellGooShape _circle(Offset centre, double radius) => (
    rect: Rect.fromCircle(center: centre, radius: math.max(0.0, radius)),
    corner: math.max(0.0, radius),
  );

  /// Where the travelling head is on a move.
  static Offset _headAt(Rect from, Rect to, double t) => Offset.lerp(
    from.center,
    to.center,
    easeInOutCubic.transform(_stage(t, kCellGooGatherEnd, kCellGooTravelEnd)),
  )!;

  /// Where the body is at [t], and what shape.
  ///
  /// A choice that changes while the body is on its way sets off again from
  /// here, rather than from the cell it was first leaving, so a quick second
  /// tap bends the journey instead of starting it over.
  static CellGooShape? bodyAt({
    Rect? from,
    Rect? to,
    required double t,
    double fromCorner = kCellGooCellCorner,
  }) {
    final radius = _radiusFor(from, to);
    if (from != null && to != null) {
      if (t < kCellGooGatherEnd) {
        return _gathered(
          from,
          fromCorner,
          radius,
          easeOutCubic.transform(_stage(t, 0, kCellGooGatherEnd)),
        );
      }
      if (t < kCellGooArriveStart) {
        return _circle(_headAt(from, to, t), radius * 0.9);
      }
      return _opened(
        to,
        radius,
        easeOutCubic.transform(_stage(t, kCellGooArriveStart, 1)),
      );
    }
    if (to != null) {
      if (t < kCellGooCondenseEnd) {
        return _circle(
          to.center,
          radius * 0.9 * easeOutCubic.transform(t / kCellGooCondenseEnd),
        );
      }
      return _opened(
        to,
        radius,
        easeOutCubic.transform(_stage(t, kCellGooCondenseEnd, 1)),
      );
    }
    if (from != null) {
      if (t < kCellGooDrawInEnd) {
        return _gathered(
          from,
          fromCorner,
          radius,
          easeInOutCubic.transform(t / kCellGooDrawInEnd),
        );
      }
      return _circle(
        from.center,
        radius * (1 - easeInCubic.transform(_stage(t, kCellGooDrawInEnd, 1))),
      );
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    final from = this.from;
    final to = this.to;
    if (from != null && to != null) {
      _move(canvas, paint, from, to);
      return;
    }
    final body = bodyAt(from: from, to: to, t: t, fromCorner: fromCorner);
    if (body != null) _blob(canvas, paint, body);
  }

  void _blob(Canvas canvas, Paint paint, CellGooShape body) {
    if (body.rect.width <= 0 || body.rect.height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(body.rect, Radius.circular(body.corner)),
      paint,
    );
  }

  void _move(Canvas canvas, Paint paint, Rect from, Rect to) {
    final radius = _radiusFor(from, to);

    // The old cell's fill gathers into a body the size of a circle.
    if (t < kCellGooGatherEnd) {
      _blob(
        canvas,
        paint,
        bodyAt(from: from, to: to, t: t, fromCorner: fromCorner)!,
      );
    }

    // The body crosses, trailing a thread back to where it came from that
    // thins as it goes and lets go before it arrives. It is slow to leave,
    // because the neck is still holding it, and slow to arrive, because it
    // is thick.
    final crossing = t > kCellGooGatherEnd * 0.5 && t < kCellGooTravelEnd;
    if (crossing) {
      final head = _headAt(from, to, t);
      final travel = easeInOutCubic.transform(
        _stage(t, kCellGooGatherEnd, kCellGooTravelEnd),
      );
      // Drawn out along the way it is going and pinched across it, most of
      // all half way over, the way a drop is while it is falling.
      final heading = to.center - from.center;
      final stretch = math.sin(math.pi * travel);
      canvas
        ..save()
        ..translate(head.dx, head.dy)
        ..rotate(heading.distance == 0 ? 0 : math.atan2(heading.dy, heading.dx))
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: radius * 1.8 * (1 + kCellGooStretch * stretch),
            height: radius * 1.8 * (1 - kCellGooPinch * stretch),
          ),
          paint,
        )
        ..restore();
      final path = head - from.center;
      final length = path.distance;
      final left = 1 - _stage(t, kCellGooArriveStart, kCellGooTravelEnd);
      if (length > 0 && left > 0) {
        final steps = math.max(2, (length / kCellGooThreadPitch).ceil());
        for (var i = 1; i < steps; i++) {
          final along = i / steps;
          final waist = 1 - (1 - kGooNeckWaist) * math.sin(along * math.pi);
          canvas.drawCircle(
            from.center + path * along,
            radius * 0.55 * waist * left,
            paint,
          );
        }
      }
    }

    // A circle opens at the new cell and widens into its shape.
    if (t >= kCellGooArriveStart) {
      _blob(canvas, paint, bodyAt(from: from, to: to, t: t)!);
    }
  }

  @override
  bool shouldRepaint(CellGooPainter old) =>
      old.from != from ||
      old.to != to ||
      old.t != t ||
      old.colour != colour ||
      old.fromCorner != fromCorner;
}
