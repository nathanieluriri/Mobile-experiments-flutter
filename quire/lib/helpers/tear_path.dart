import 'dart:math' as math;
import 'dart:ui';

/// How far apart the teeth of a tear sit.
const kTearStep = 8.0;

/// How far a tooth wanders either side of the tear line.
const kTearAmplitude = 5.0;

/// Where the tear crosses a damaged sheet: the bottom 40 percent is missing.
const kTearFraction = 0.6;

/// How thick the exposed back of the sheet reads along the tear.
const kTearThickness = 1.5;

/// The ragged edge of a damaged sheet, as a left to right polyline across a
/// sheet [width] wide with its tear line at [y].
///
/// The jitter is drawn from `Random(42)` and built once by the caller, never
/// per frame: a tear that reshuffled while you looked at it would read as
/// static, and a golden of it would never repeat.
List<Offset> tearPolyline(
  double width,
  double y, {
  double step = kTearStep,
  double amplitude = kTearAmplitude,
  int seed = 42,
}) {
  final random = math.Random(seed);
  final points = <Offset>[Offset(0, y)];
  for (var x = step; x < width; x += step) {
    points.add(Offset(x, y + (random.nextDouble() * 2 - 1) * amplitude));
  }
  points.add(Offset(width, y));
  return points;
}

/// The whole of a damaged sheet: everything above [tear], closed along the
/// sheet's other three edges.
///
/// The path is built from an already generated polyline so the caller can hold
/// one tear for the life of the sheet and hand it to both the fill and the
/// hairline.
Path tornSheetPath(double width, List<Offset> tear) {
  final path = Path()..moveTo(0, 0)..lineTo(width, 0);
  for (final point in tear.reversed) {
    path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

/// The tear itself, as an open path, for the hairline and the exposed back.
Path tearEdgePath(List<Offset> tear) {
  final path = Path()..moveTo(tear.first.dx, tear.first.dy);
  for (final point in tear.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path;
}
