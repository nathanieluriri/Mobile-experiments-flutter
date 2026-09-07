import 'package:flutter/physics.dart';

const fabDiameter = 64.0;
const actionDiameter = 56.0;

const fabCanvasWidth = 112.0;
const fabCanvasHeight = 320.0;
const fabCanvasBottomOffset = 8.0;
const fabBottomMargin = 24.0;

const fabCenterX = fabCanvasWidth / 2;
const fabCenterY = fabCanvasHeight - fabBottomMargin - fabDiameter / 2;

const voiceActionOffsetY = -94.0;
const videoActionOffsetY = -188.0;

const openSpring = SpringDescription(mass: 1, stiffness: 130, damping: 14);
const closeSpring = SpringDescription(mass: 1, stiffness: 190, damping: 17);
const videoOpenSpring = SpringDescription(mass: 1, stiffness: 130, damping: 13);
const actionStagger = Duration(milliseconds: 60);

const gooBlurSigma = 9.0;

/// Blur then threshold: the alpha row multiplies by 32 and subtracts 14, in a
/// colour space where 1.0 is opaque. Flutter states the translation column in
/// 0..255, so -14 is written as -14 * 255.
const gooAlphaThresholdMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 32, -3570, //
];

const actionScaleInputRange = [0.6, 1.0];
const actionScaleOutputRange = [0.4, 1.0];
const actionOpacityInputRange = [0.65, 1.0];
const actionOpacityOutputRange = [0.0, 1.0];

/// Gaussian sigma and white wash the backdrop reaches when fully open.
const backdropBlurSigma = 9.6;
const backdropWashOpacity = 0.12;

const plusIconOpenRotationDegrees = 135.0;

const plusIconSize = 30.0;
const videoIconSize = 22.0;
const voiceIconSize = 20.0;

/// Maps [value] from [inputRange] to [outputRange], clamped at both ends.
double interpolateClamped(double value, List<double> inputRange, List<double> outputRange) {
  final t = ((value - inputRange[0]) / (inputRange[1] - inputRange[0])).clamp(0.0, 1.0);
  return outputRange[0] + (outputRange[1] - outputRange[0]) * t;
}
