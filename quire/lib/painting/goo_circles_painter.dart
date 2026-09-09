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

  @override
  bool shouldRepaint(GooCirclesPainter oldDelegate) =>
      oldDelegate.buttonDiameter != buttonDiameter ||
      !listEquals(oldDelegate.actionCentresY, actionCentresY);
}
