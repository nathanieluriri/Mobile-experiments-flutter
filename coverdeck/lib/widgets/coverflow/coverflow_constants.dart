import 'dart:math' as math;

export '../../theme/metrics.dart' show interpolate;

/// Tilt of a cover one step away from the focus, in degrees.
const maxTiltDeg = 62.0;

/// Scale of a cover one step away from the focus.
const sideScale = 0.8;

/// Height of the reflection as a fraction of the cover.
const reflectionRatio = 0.45;

/// Distance from the eye to the deck, in points.
const perspective = 900.0;

/// Gap between the cover and its reflection.
const reflectionGap = 3.0;

/// Corner radius of a cover.
const coverRadius = 6.0;

/// Cover width for a screen [width] points wide.
double coverSize(double width) => math.min(width * 0.56, 250);

/// Hyperbolic tangent, which eases the focused cover out of the stack.
double tanh(double x) {
  if (x > 20) return 1;
  if (x < -20) return -1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Stacking step of the cover at [index] when the deck sits at [scrollX].
/// Covers that round to the same step are stacked in album order.
int coverZIndex(int index, double scrollX) => (1000 - (index - scrollX).abs() * 10).round();
