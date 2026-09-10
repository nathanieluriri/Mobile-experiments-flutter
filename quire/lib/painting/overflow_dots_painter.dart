import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme/metrics.dart';

/// The three dots, and the one dot they become while their menu is open.
///
/// As the goo swells at the button the outer two dots slide into the middle
/// one, so the three are absorbed into a single dot at the centre of the body
/// that came out of them. When the menu goes back in they spread out again.
/// Nothing new is drawn: the open state is made of the dots, at the size the
/// dots already are, which is what lets it read as the control changing state
/// rather than as a second glyph arriving.
///
/// It is drawn over the goo rather than under it, because a body that
/// swallowed the control it came out of would leave nothing to read.
class OverflowDotsPainter extends CustomPainter {
  const OverflowDotsPainter({required this.t, required this.colour});

  /// 0 with the menu shut, 1 with it open.
  final double t;

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final open = t.clamp(0.0, 1.0);
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = colour;
    final step = kOverflowDot + kOverflowDotGap;
    // The outer dots' distance from the middle: a full step at rest, nothing
    // once they have been drawn in.
    final reach = ui.lerpDouble(step, 0, open)!;
    for (final side in <double>[-1, 0, 1]) {
      canvas.drawCircle(
        centre + Offset(0, side * reach),
        kOverflowDot / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(OverflowDotsPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.colour != colour;
}
