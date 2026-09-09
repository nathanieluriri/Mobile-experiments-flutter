import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import '../theme/metrics.dart';

/// The three lines of the menu glyph, and the arrow they turn into.
///
/// It takes a progress rather than a controller because the drawer's own
/// position is the only thing that decides what this looks like. Half a
/// drawer is half an arrow, whether the panel got there under a spring or
/// under a finger, and there is no second animation that could disagree with
/// the panel about where the gesture has reached.
class HamburgerPainter extends CustomPainter {
  const HamburgerPainter({required this.progress, required this.color});

  /// 0 with the drawer shut, 1 with it fully in.
  final double progress;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color
      ..strokeWidth = kBurgerThickness
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // The whole glyph walks left as it turns, so the arrow ends up where a
    // back arrow belongs rather than where a menu button did.
    final left = (size.width - kBurgerLine) / 2 - kBurgerShift * p;
    final stack = kBurgerThickness * 3 + kBurgerGap * 2;
    final top = (size.height - stack) / 2 + kBurgerThickness / 2;
    final middle = top + kBurgerThickness + kBurgerGap;
    final bottom = middle + kBurgerThickness + kBurgerGap;

    // The middle line holds: it is the arrow's shaft the whole way through,
    // which is what stops the morph reading as three unrelated lines moving.
    canvas.drawLine(
      Offset(left, middle),
      Offset(left + kBurgerLine, middle),
      paint,
    );
    _arm(canvas, paint, left, top, p, -kBurgerAngle);
    _arm(canvas, paint, left, bottom, p, kBurgerAngle);
  }

  /// One of the two lines that become the arrow's head.
  ///
  /// It shortens towards its left end, so the end it pivots about is the end
  /// that travels, and the two heads meet over the shaft's left end instead of
  /// over its middle.
  void _arm(
    Canvas canvas,
    Paint paint,
    double left,
    double y,
    double p,
    double degrees,
  ) {
    final length = lerpDouble(kBurgerLine, kBurgerLineShort, p)!;
    final pivot = Offset(left + length, y);
    final radians = degrees * p * math.pi / 180;
    final free = pivot +
        Offset(-length * math.cos(radians), -length * math.sin(radians));
    canvas.drawLine(pivot, free, paint);
  }

  @override
  bool shouldRepaint(HamburgerPainter old) =>
      old.progress != progress || old.color != color;
}
