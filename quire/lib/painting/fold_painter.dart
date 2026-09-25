import 'package:flutter/rendering.dart';

import '../helpers/fold_geometry.dart';

/// How strongly the front of a sheet shows through its own flap.
///
/// It is one extra save layer and it is the single detail that convinces the
/// eye a sheet has two sides in a still frame.
const kShowThroughOpacity = 0.10;

/// Draws a peeled corner over a sheet: the torn away region first, then the
/// flap on top.
///
/// The torn away region is a flat [background] unless [backLayer] is given, in
/// which case it is whatever the back of this sheet actually holds. The flap is
/// [flapColor], with [showThrough] drawn over it mirrored about the fold line
/// at [kShowThroughOpacity].
class FoldPainter extends CustomPainter {
  const FoldPainter({
    required double this.dragX,
    required double this.dragY,
    required this.background,
    required this.flapColor,
    this.corner = Corner.topRight,
    this.backLayer,
    this.showThrough,
  }) : restInset = 0;

  /// A corner turned down by [restInset] and left there, for anything that
  /// wants the folded look without a finger on it.
  const FoldPainter.atRest({
    required this.restInset,
    required this.background,
    required this.flapColor,
    this.corner = Corner.topRight,
    this.backLayer,
    this.showThrough,
  })  : dragX = null,
        dragY = null;

  /// Where the corner has been pulled to, or null to sit at [restInset].
  final double? dragX;
  final double? dragY;

  /// How far in from the corner an untouched fold sits.
  final double restInset;

  /// Which corner turns.
  final Corner corner;

  /// Fills the torn away region when there is no [backLayer].
  final Color background;

  final Color flapColor;

  /// What the sheet holds on its back, painted into the torn away region in
  /// the sheet's own coordinates.
  final CustomPainter? backLayer;

  /// The sheet's own front content, redrawn on the flap mirrored about the
  /// fold line.
  final CustomPainter? showThrough;

  @override
  void paint(Canvas canvas, Size size) {
    final restX = corner.mirrorsX ? restInset : size.width - restInset;
    final restY = corner.mirrorsY ? size.height - restInset : restInset;
    final geometry = computeFoldGeometry(
      size.width,
      size.height,
      dragX ?? restX,
      dragY ?? restY,
      corner: corner,
    );
    if (geometry.clipped.length < 3) {
      return;
    }

    final clipped = Path()..addPolygon(geometry.clipped, true);
    if (backLayer case final back?) {
      canvas.save();
      canvas.clipPath(clipped);
      back.paint(canvas, size);
      canvas.restore();
    } else {
      canvas.drawPath(clipped, Paint()..color = background);
    }

    if (geometry.flap.length < 3) {
      return;
    }
    final flap = Path()..addPolygon(geometry.flap, true);
    canvas.drawPath(flap, Paint()..color = flapColor);

    if (showThrough case final front?) {
      canvas.save();
      canvas.clipPath(flap);
      // A layer paint carries an opacity and nothing else: only the alpha is
      // read when the layer composites, which is why no palette colour is
      // named here.
      canvas.saveLayer(
        flap.getBounds(),
        Paint()
          ..color = const Color.fromARGB(255, 0, 0, 0)
              .withValues(alpha: kShowThroughOpacity),
      );
      canvas.transform(geometry.reflection.storage);
      front.paint(canvas, size);
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FoldPainter oldDelegate) =>
      oldDelegate.dragX != dragX ||
      oldDelegate.dragY != dragY ||
      oldDelegate.restInset != restInset ||
      oldDelegate.corner != corner ||
      oldDelegate.background != background ||
      oldDelegate.flapColor != flapColor ||
      oldDelegate.backLayer != backLayer ||
      oldDelegate.showThrough != showThrough;
}
