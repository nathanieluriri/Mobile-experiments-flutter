import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../theme/metrics.dart';

/// Which corner of a sheet a fold turns.
///
/// The maths is written once, for the top right corner. Every other corner is
/// the same fold with the input mirrored on the way in and the output mirrored
/// on the way back, which is why a card folding at the bottom right and a
/// flipped sheet folding at the top left share one function and one set of
/// tests.
enum Corner {
  topRight,
  bottomRight,
  topLeft,
  bottomLeft;

  /// Whether this corner needs the x axis mirrored to become [topRight].
  bool get mirrorsX => this == Corner.topLeft || this == Corner.bottomLeft;

  /// Whether this corner needs the y axis mirrored to become [topRight].
  bool get mirrorsY => this == Corner.bottomRight || this == Corner.bottomLeft;
}

/// The two polygons that make a peeled corner, and the line they meet at.
class FoldGeometry {
  const FoldGeometry({
    required this.clipped,
    required this.flap,
    required this.foldMid,
    required this.foldNormal,
    required this.corner,
    required this.point,
  });

  /// The region of the sheet on the far side of the fold line, the part that
  /// has been torn away. Painted in the ground, or in whatever the back of the
  /// sheet holds.
  final List<Offset> clipped;

  /// [clipped] reflected across the fold line, index for index. Painted in the
  /// flap colour, so it reads as the back of the paper.
  final List<Offset> flap;

  /// A point on the fold line: the midpoint between [corner] and [point].
  final Offset foldMid;

  /// Unit normal to the fold line, pointing at [corner].
  final Offset foldNormal;

  /// The corner this fold turns, in sheet coordinates.
  final Offset corner;

  /// Where the finger is, after the edge margin has pulled it inside.
  final Offset point;

  /// [p] reflected across the fold line.
  Offset reflect(Offset p) {
    final side =
        (p.dx - foldMid.dx) * foldNormal.dx + (p.dy - foldMid.dy) * foldNormal.dy;
    return Offset(
      p.dx - 2 * side * foldNormal.dx,
      p.dy - 2 * side * foldNormal.dy,
    );
  }

  /// The same reflection as a matrix, so a canvas can draw the sheet's own
  /// front content onto the flap without walking every point.
  Matrix4 get reflection {
    final nx = foldNormal.dx;
    final ny = foldNormal.dy;
    final d = foldMid.dx * nx + foldMid.dy * ny;
    // Columns of `p - 2 (p . n - d) n`.
    return Matrix4(
      1 - 2 * nx * nx, -2 * nx * ny, 0, 0, //
      -2 * nx * ny, 1 - 2 * ny * ny, 0, 0, //
      0, 0, 1, 0, //
      2 * d * nx, 2 * d * ny, 0, 1,
    );
  }
}

/// Clips the `width` x `height` sheet against the fold line, which is the
/// perpendicular bisector between [corner] and the drag point, then reflects
/// the clipped part across it.
///
/// Reflecting across the bisector maps the corner exactly onto the drag point,
/// which is why the flap always lands under the finger. It is a true
/// reflection, never a skew: a skew would stretch the paper, and paper does not
/// stretch.
FoldGeometry computeFoldGeometry(
  double width,
  double height,
  double rawX,
  double rawY, {
  Corner corner = Corner.topRight,
}) {
  double inX(double x) => corner.mirrorsX ? width - x : x;
  double inY(double y) => corner.mirrorsY ? height - y : y;
  Offset out(double x, double y) => Offset(inX(x), inY(y));

  final pointX = math.min(inX(rawX), width - kFoldEdgeMargin);
  final pointY = math.max(inY(rawY), kFoldEdgeMargin);

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
      clipped.add(out(cornerXs[i], cornerYs[i]));
      flap.add(out(
        cornerXs[i] - 2 * sides[i] * normalX,
        cornerYs[i] - 2 * sides[i] * normalY,
      ));
    }
    if (sides[i] * sides[j] < 0) {
      final t = sides[i] / (sides[i] - sides[j]);
      final crossing = out(
        cornerXs[i] + t * (cornerXs[j] - cornerXs[i]),
        cornerYs[i] + t * (cornerYs[j] - cornerYs[i]),
      );
      clipped.add(crossing);
      flap.add(crossing);
    }
  }

  // Mirroring flips the sign of the axis it mirrors, for the normal as well as
  // for every point, so the fold line comes back out in sheet coordinates.
  return FoldGeometry(
    clipped: clipped,
    flap: flap,
    foldMid: out(midX, midY),
    foldNormal: Offset(
      corner.mirrorsX ? -normalX : normalX,
      corner.mirrorsY ? -normalY : normalY,
    ),
    corner: out(width, 0),
    point: out(pointX, pointY),
  );
}
