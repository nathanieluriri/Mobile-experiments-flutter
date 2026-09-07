import 'package:flutter/widgets.dart';

/// Thinnest line the screen can draw, one physical pixel.
double hairlineWidth(BuildContext context) => 1 / MediaQuery.devicePixelRatioOf(context);

/// Piecewise linear map of [x] from [input] onto [output], clamped at both ends.
///
/// [input] must be ascending and the two lists must be the same length.
double interpolate(double x, List<double> input, List<double> output) {
  if (x <= input.first) return output.first;
  if (x >= input.last) return output.last;
  for (var i = 1; i < input.length; i++) {
    if (x <= input[i]) {
      final span = input[i] - input[i - 1];
      final t = span == 0 ? 0.0 : (x - input[i - 1]) / span;
      return output[i - 1] + (output[i] - output[i - 1]) * t;
    }
  }
  return output.last;
}
