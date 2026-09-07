import 'dart:math' as math;
import 'dart:ui';

import '../theme/metrics.dart';

/// The two polygons that make a peeled corner: the part of the note that has
/// been folded away, and where it lands after folding.
class FoldGeometry {
  const FoldGeometry(this.clipped, this.flap);

  /// The region of the note rectangle on the far side of the fold line. Painted
  /// in the screen background so the note reads as torn away there.
  final List<Offset> clipped;

  /// [clipped] reflected across the fold line. Painted in the shaded note
  /// colour, so it reads as the back of the paper.
  final List<Offset> flap;
}

/// Clips the `width` x `height` note rectangle against the fold line, which is
/// the perpendicular bisector between the top-right corner and the drag point,
/// then reflects the clipped part across it.
///
/// Reflecting across the bisector maps the corner exactly onto the drag point,
/// which is why the flap always lands under the finger.
FoldGeometry computeFoldGeometry(
  double width,
  double height,
  double rawX,
  double rawY,
) {
  final pointX = math.min(rawX, width - kFoldEdgeMargin);
  final pointY = math.max(rawY, kFoldEdgeMargin);

  final midX = (width + pointX) / 2;
  final midY = pointY / 2;
  var normalX = width - pointX;
  var normalY = -pointY;
  final normalLength = math.sqrt(normalX * normalX + normalY * normalY);
  normalX /= normalLength;
  normalY /= normalLength;

  final cornerXs = <double>[0, width, width, 0];
  final cornerYs = <double>[0, 0, height, height];
  final sides = List<double>.filled(4, 0);
  for (var i = 0; i < 4; i++) {
    sides[i] = (cornerXs[i] - midX) * normalX + (cornerYs[i] - midY) * normalY;
  }

  final clipped = <Offset>[];
  final flap = <Offset>[];
  for (var i = 0; i < 4; i++) {
    final j = (i + 1) % 4;
    if (sides[i] >= 0) {
      clipped.add(Offset(cornerXs[i], cornerYs[i]));
      flap.add(
        Offset(
          cornerXs[i] - 2 * sides[i] * normalX,
          cornerYs[i] - 2 * sides[i] * normalY,
        ),
      );
    }
    if (sides[i] * sides[j] < 0) {
      final t = sides[i] / (sides[i] - sides[j]);
      final crossing = Offset(
        cornerXs[i] + t * (cornerXs[j] - cornerXs[i]),
        cornerYs[i] + t * (cornerYs[j] - cornerYs[i]),
      );
      clipped.add(crossing);
      flap.add(crossing);
    }
  }
  return FoldGeometry(clipped, flap);
}
