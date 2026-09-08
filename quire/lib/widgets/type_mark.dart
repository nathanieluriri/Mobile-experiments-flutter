import 'package:flutter/widgets.dart';

import '../helpers/fold_geometry.dart';
import '../painting/fold_painter.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';

/// How far up from the mark's bottom edge the extension letters sit.
const kTypeMarkBaseline = 9.0;

/// The folded format mark: a small index tab carrying three letters.
///
/// A type mark is not paper, it is a tab, which is why its flap carries a
/// format colour where a sheet's flap carries [AppColors.leafFlap]. Those five
/// hues appear here and on nothing else, so a colour always means a format and
/// can never be mistaken for `thread` or `marker`.
class TypeMark extends StatelessWidget {
  const TypeMark({
    super.key,
    required this.letters,
    required this.chroma,
    this.width = kTypeMarkWidth,
    this.height = kTypeMarkHeight,
    this.foldInset = kTypeMarkFoldInset,
    this.corner = Corner.bottomRight,
  });

  /// The extension, written uppercase in the source so a golden reads what the
  /// source says.
  final String letters;

  /// The format's own hue.
  final Color chroma;

  final double width;
  final double height;
  final double foldInset;
  final Corner corner;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _TypeMarkPainter(chroma: chroma, foldInset: foldInset, corner: corner),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Baseline(
                baseline: height - kTypeMarkBaseline,
                baselineType: TextBaseline.alphabetic,
                child: Text(
                  letters,
                  textAlign: TextAlign.center,
                  style: AppText.micro.copyWith(color: chroma),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tab itself: a leaf rectangle with a hairline round it and one corner
/// turned down in the format's colour.
class _TypeMarkPainter extends CustomPainter {
  const _TypeMarkPainter({
    required this.chroma,
    required this.foldInset,
    required this.corner,
  });

  final Color chroma;
  final double foldInset;
  final Corner corner;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = AppColors.leaf);
    FoldPainter.atRest(
      restInset: foldInset,
      corner: corner,
      background: AppColors.leaf,
      flapColor: chroma,
    ).paint(canvas, size);
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = AppColors.rule
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_TypeMarkPainter old) =>
      old.chroma != chroma ||
      old.foldInset != foldInset ||
      old.corner != corner;
}
