import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../constants/gooey_fab.dart';
import '../theme/colors.dart';

/// The solid circles the goo layer blurs and thresholds: one per action at its
/// current height, and the button itself.
///
/// They are drawn solid and identical in colour on purpose. The layer above
/// blurs the lot as one image, so any difference in alpha or hue between two
/// circles would survive the threshold as a seam through a body that is meant
/// to be one piece.
class GooCirclesPainter extends CustomPainter {
  const GooCirclesPainter({
    required this.actionCentresY,
    required this.buttonDiameter,
  });

  /// The centre of each action's circle, in canvas coordinates. All of them
  /// sit on [kFabCenterX].
  final List<double> actionCentresY;

  /// The button's circle, which narrows as the button itself narrows from a 60
  /// squircle to a 56 circle.
  final double buttonDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.accent;
    for (final centreY in actionCentresY) {
      _neck(canvas, paint, centreY);
      canvas.drawCircle(
        Offset(kFabCenterX, centreY),
        kGooActionDiameter / 2,
        paint,
      );
    }
    canvas.drawCircle(
      const Offset(kFabCenterX, kFabCenterY),
      buttonDiameter / 2,
      paint,
    );
  }

  /// Strings circles between the button and an action so the two read as one
  /// body being pulled apart rather than as two circles moving apart.
  ///
  /// The circles taper towards the middle, so the join has a waist, and the
  /// whole run thins to nothing as the action reaches [kGooNeckBreak]. Past
  /// that this draws nothing at all and the goo has let go.
  void _neck(Canvas canvas, Paint paint, double centreY) {
    final travelled = (centreY - kFabCenterY).abs();
    if (travelled <= 0 || travelled >= kGooNeckBreak) return;
    final left = 1 - travelled / kGooNeckBreak;
    final buttonRadius = buttonDiameter / 2;
    const actionRadius = kGooActionDiameter / 2;
    for (var i = 1; i <= kGooNeckCircles; i++) {
      final along = i / (kGooNeckCircles + 1);
      // Thinnest at the waist and fullest at either end, so the neck meets
      // each circle at that circle's own width.
      final waist = 1 - (1 - kGooNeckWaist) * math.sin(along * math.pi);
      final radius =
          ui.lerpDouble(buttonRadius, actionRadius, along)! * waist * left;
      if (radius <= 0) continue;
      canvas.drawCircle(
        Offset(kFabCenterX, ui.lerpDouble(kFabCenterY, centreY, along)!),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(GooCirclesPainter oldDelegate) =>
      oldDelegate.buttonDiameter != buttonDiameter ||
      !listEquals(oldDelegate.actionCentresY, actionCentresY);
}
