import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// How many lobes the wash is made of.
///
/// One circle blurred and thresholded is still a circle. Five, each breathing
/// on its own phase, merge into something with a shoreline.
const kWashLobes = 5;

/// How far each lobe sits out from the finger, as a share of the blob's
/// radius. The lobes draw together as the wash floods, so what fills the
/// control is one body and not a flower.
const kWashLobeSpread = 0.55;

/// The blob's radius once it has fully welled up under a held finger.
const kWashWell = 26.0;

/// The wash a press leaves inside a control.
///
/// Under the finger a lobed blob wells up. On release it floods out to the
/// control's far corners, which the caller clips to the control's own shape,
/// and drains as it goes. Everything here is solid and one colour; the blur
/// and threshold above merge the lobes, and the caller sets the transparency
/// round the outside, because the threshold would throw away a translucent
/// source before it ever reached the screen.
class WashPainter extends CustomPainter {
  const WashPainter({
    required this.at,
    required this.well,
    required this.flood,
    required this.colour,
  });

  /// The finger, in the control's coordinates.
  final Offset at;

  /// 0 to 1 as the blob wells up under a held finger.
  final double well;

  /// 0 to 1 as it floods the control after the finger lifts.
  final double flood;

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (well <= 0 && flood <= 0) return;
    final paint = Paint()..color = colour;
    // Far enough to reach every corner from wherever the finger landed.
    var reach = 0.0;
    for (final corner in <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      reach = math.max(reach, (corner - at).distance);
    }
    final radius = ui.lerpDouble(kWashWell * well, reach + kWashWell, flood)!;
    final spread = radius * kWashLobeSpread * (1 - flood);
    for (var i = 0; i < kWashLobes; i++) {
      final angle = i * 2 * math.pi / kWashLobes;
      // Each lobe breathes on its own phase, so the blob is never a disc and
      // never the same shape twice across a press.
      final breathe = 0.8 + 0.2 * math.sin(well * math.pi * (1 + i * 0.37));
      canvas.drawCircle(
        at + Offset(math.cos(angle), math.sin(angle)) * spread,
        radius * breathe,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WashPainter oldDelegate) =>
      oldDelegate.at != at ||
      oldDelegate.well != well ||
      oldDelegate.flood != flood ||
      oldDelegate.colour != colour;
}
