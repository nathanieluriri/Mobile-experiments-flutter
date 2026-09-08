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
    this.sheetColor = AppColors.leaf,
    this.backColor = AppColors.leafBack,
    this.edgeColor = AppColors.damage,
    this.thickness = kTearThickness,
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

  @override
  void paint(Canvas canvas, Size size) {
    if (tear.length < 2) {
      return;
    }
    final edge = tearEdgePath(tear);
    canvas.drawPath(
      tornSheetPath(size.width, tear),
      Paint()..color = sheetColor,
    );
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
      old.thickness != thickness;
}
