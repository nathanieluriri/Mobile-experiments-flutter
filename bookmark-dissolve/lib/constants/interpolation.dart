/// Clamps [value] to the unit range.
double clamp01(double value) => value < 0
    ? 0
    : value > 1
    ? 1
    : value;

/// The Hermite ease both the particle motion and the particle fade run through.
double smoothstep(double t) => t * t * (3 - 2 * t);

/// Maps [value] through the piecewise ramp [stops] to [values], clamped at both
/// ends. Mirrors the interpolate call the canvas drives the frost with.
double interpolate(double value, List<double> stops, List<double> values) {
  if (value <= stops.first) {
    return values.first;
  }
  for (var i = 1; i < stops.length; i++) {
    if (value <= stops[i]) {
      final span = stops[i] - stops[i - 1];
      final t = span == 0 ? 1.0 : (value - stops[i - 1]) / span;
      return values[i - 1] + (values[i] - values[i - 1]) * t;
    }
  }
  return values.last;
}
