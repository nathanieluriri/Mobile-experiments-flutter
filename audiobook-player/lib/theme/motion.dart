import 'package:flutter/physics.dart';

/// The spring the sheet settles on, whether it was tapped or flung.
const sheetSpring = SpringDescription(mass: 0.9, stiffness: 260, damping: 28);

/// A flick past this many logical pixels per second decides the sheet on its
/// own, whichever way it was already leaning.
const flickVelocity = 500.0;

/// How long a picture takes to fade in once it is decoded.
const artworkFadeDuration = Duration(milliseconds: 250);

/// The same shape as the animation library's `interpolate`: a piecewise linear
/// map from [input] to [output]. Outside the ends it keeps extending the first
/// and last segment unless [clamp] is set.
double interpolate(
  double x,
  List<double> input,
  List<double> output, {
  bool clamp = false,
}) {
  if (clamp) {
    if (x <= input.first) return output.first;
    if (x >= input.last) return output.last;
  }
  var segment = 0;
  while (segment < input.length - 2 && x >= input[segment + 1]) {
    segment++;
  }
  final span = input[segment + 1] - input[segment];
  final t = span == 0 ? 0.0 : (x - input[segment]) / span;
  return output[segment] + (output[segment + 1] - output[segment]) * t;
}
