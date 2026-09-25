import 'package:flutter/rendering.dart';

import '../theme/colors.dart';
import '../theme/metrics.dart';

/// What a cell has left to say once its column is only twelve points wide.
///
/// A folded column is not a hidden column: it keeps its data as a shape, so a
/// nine column workbook reads as one open column beside a strip chart and the
/// reader can see where the interesting rows are before opening anything.
enum SpineMark {
  /// Nothing in the cell.
  none,

  /// A number, drawn as a bar against the column's largest magnitude.
  bar,

  /// Anything else with text in it, drawn as a dot.
  dot,
}

/// One cell of a folded column, reduced to the mark it draws.
class SpineValue {
  const SpineValue(this.mark, {this.extent = 0, this.found = false});

  /// Nothing, a bar, or a dot.
  final SpineMark mark;

  /// How large this number is against the largest in its column, 0 to 1.
  /// Meaningless for anything but [SpineMark.bar].
  final double extent;

  /// True when the cell holds a search match, which colours the mark
  /// [AppColors.found] so folding a column can never hide a result.
  final bool found;
}

/// How wide a bar is drawn for a value at [extent] of its column's largest.
///
/// The floor of one point is what stops a small value vanishing: a row with a
/// value in it must never look the same as an empty row.
double spineBarWidth(double extent) =>
    (kSpineBarMax * extent).clamp(1.0, kSpineBarMax);

/// Draws one folded cell's mark: a two point bar from the spine's left edge,
/// or a four point dot in the middle of it.
///
/// The bar grows from the left edge rather than from the centre so a run of
/// them down a column reads as a chart with a shared baseline, which is the
/// only way twelve points of width can carry a magnitude.
class SpineGlyphPainter extends CustomPainter {
  const SpineGlyphPainter(this.value);

  final SpineValue value;

  @override
  void paint(Canvas canvas, Size size) {
    if (value.mark == SpineMark.none) return;
    final paint = Paint()
      ..color = value.found ? AppColors.found : AppColors.inkFaint;
    final middle = size.height / 2;
    switch (value.mark) {
      case SpineMark.none:
        return;
      case SpineMark.bar:
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            middle - kSpineBarHeight / 2,
            spineBarWidth(value.extent).clamp(0, size.width),
            kSpineBarHeight,
          ),
          paint,
        );
      case SpineMark.dot:
        canvas.drawCircle(
          Offset(size.width / 2, middle),
          kSpineDot / 2,
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(SpineGlyphPainter old) =>
      old.value.mark != value.mark ||
      old.value.extent != value.extent ||
      old.value.found != value.found;
}
