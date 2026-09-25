import 'package:flutter/rendering.dart';

import '../helpers/tear_path.dart';
import '../theme/colors.dart';

/// Draws a sheet that has actually been torn: everything below the tear line
/// is gone, and the ground shows through the loss.
///
/// A document that will not open is not a dialog and not an alert. It is a
/// damaged piece of paper, so the sheet itself carries the damage.
class TearPainter extends CustomPainter {
  const TearPainter({
    required this.tear,
    this.sheetColor = AppColors.surface,
    this.backColor = AppColors.leafBack,
    this.edgeColor = AppColors.damage,
    this.thickness = kTearThickness,
    this.edgeWidth = 1,
  });

  /// The ragged edge, built once from `Random(42)` and held for the life of
  /// the sheet. Rebuilding it per frame would make it read as static.
  final List<Offset> tear;

  final Color sheetColor;

  /// The exposed back of the sheet along the tear, which is what gives the
  /// paper thickness.
  final Color backColor;

  /// The hairline along the tear itself.
  final Color edgeColor;

  final double thickness;

  /// How wide the sheet's own rule is, in logical units. One physical pixel at
  /// the view's device pixel ratio.
  final double edgeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (tear.length < 2) {
      return;
    }
    final edge = tearEdgePath(tear);
    final body = tornSheetPath(size.width, tear);
    canvas.drawPath(body, Paint()..color = sheetColor);
    // The whole outline, tear included. The exposed back and the damage
    // hairline are drawn over the torn part straight after, so what survives
    // of this is the rule along the three edges that did not give way.
    //
    // Clipped to the sheet and stroked at twice the width, which lands the
    // rule wholly inside the paper. A centred stroke would straddle the sheet
    // edge and spread one physical pixel across two.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawPath(
      body,
      Paint()
        ..color = AppColors.hairline
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth * 2,
    );
    canvas.restore();
    canvas.save();
    canvas.translate(0, thickness);
    canvas.drawPath(
      edge,
      Paint()
        ..color = backColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness * 2,
    );
    canvas.restore();
    canvas.drawPath(
      edge,
      Paint()
        ..color = edgeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(TearPainter old) =>
      old.tear != tear ||
      old.sheetColor != sheetColor ||
      old.backColor != backColor ||
      old.edgeColor != edgeColor ||
      old.thickness != thickness ||
      old.edgeWidth != edgeWidth;
}
