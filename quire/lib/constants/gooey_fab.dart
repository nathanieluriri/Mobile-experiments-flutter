import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// One action the button opens into: what it shows, what it says, and how far
/// it rises from the button's centre.
///
/// A record rather than a class because nothing here has behaviour, and
/// keeping the three of them in one list is what lets the controller stagger
/// them by index instead of naming each one twice.
typedef FabAction = ({IconData glyph, String label, double offsetY});

/// The three actions, bottom to top. The nearest one to the thumb is the one
/// this app exists for.
const kFabActions = <FabAction>[
  (glyph: LucideIcons.folder, label: 'Open a file', offsetY: -82.0),
  (glyph: LucideIcons.penLine, label: 'Sign a PDF', offsetY: -152.0),
  (glyph: LucideIcons.clock, label: 'Recent', offsetY: -222.0),
];

// The button.

/// The resting button is a squircle, not a circle: at rest it is a piece of
/// the shell's chrome, and it only becomes a circle once it is the thing you
/// are inside.
const kFabRestSize = 60.0;
const kFabRestRadius = 18.0;

/// Open, it is a circle: 56 across, so its radius is half of that.
const kFabOpenSize = 56.0;
const kFabOpenRadius = kFabOpenSize / 2;

/// The plus glyph, which the open spring turns 135 degrees into a close.
const kFabGlyphSize = 26.0;
const kFabOpenRotationDegrees = 135.0;

// A pill.

const kPillHeight = 52.0;
const kPillRadius = kPillHeight / 2;
const kPillPadding = 20.0;
const kPillGlyphSize = 20.0;
const kPillGap = 12.0;

// The canvas the button and its pills live in, pinned to the bottom right of
// whatever the button is stacked over.

const kFabCanvasWidth = 220.0;
const kFabCanvasHeight = 340.0;
const kFabCanvasBottomOffset = 8.0;
const kFabRightMargin = 24.0;
const kFabBottomMargin = 24.0;

/// The button's centre. Every goo circle sits on this vertical line, including
/// the round right end of each pill, which is what keeps the neck between two
/// of them vertical instead of leaning.
const kFabCenterX = kFabCanvasWidth - kFabRightMargin - kFabRestSize / 2;
const kFabCenterY = kFabCanvasHeight - kFabBottomMargin - kFabRestSize / 2;

// The goo.

const kGooBlurSigma = 9.0;

/// The circles the goo layer draws, a little inside the shapes drawn over
/// them. Blur then threshold puts the blob's edge about a pixel outside the
/// circle it came from, and a pixel of `accent` showing round the open
/// `accentBright` button would read as a rim rather than as goo.
const kGooActionDiameter = 50.0;
const kGooButtonRestDiameter = 56.0;
const kGooButtonOpenDiameter = 52.0;

/// The circles strung between the button and each action while the two are
/// still one body.
///
/// One circle per action is enough for the nearest, which never travels far
/// enough to leave the button. The furthest travels 222 and would otherwise
/// separate within a few frames and fly up on its own, and three circles
/// drifting apart is not goo, it is three circles. These fill the gap so the
/// body stretches into a neck instead.
const kGooNeckCircles = 3;

/// How far an action can get before its neck has thinned away to nothing.
///
/// Goo stretches and then it lets go. Past this the action is its own body,
/// which is why the pills arrive as three separate things and not as a comb.
const kGooNeckBreak = 132.0;

/// How thin the neck is at its waist, against the circles it runs between. A
/// neck as fat as its ends is a sausage.
const kGooNeckWaist = 0.62;

/// Blur then threshold: the alpha row multiplies by 32 and subtracts 14, in a
/// colour space where 1.0 is opaque. Flutter states the translation column in
/// 0..255, so -14 is written as -14 * 255.
///
/// This matrix is the whole effect. Two circles blurred into one layer overlap
/// in the gap between them, their alphas add, and the threshold snaps that sum
/// back to a hard edge, so the pair reads as one body joined by a neck. Fading
/// or scaling the circles instead would just be two circles fading.
const kGooAlphaThresholdMatrix = <double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 32, -3570, //
];

// Motion.

const kFabOpenSpring = SpringDescription(mass: 1, stiffness: 130, damping: 14);
const kFabCloseSpring = SpringDescription(mass: 1, stiffness: 190, damping: 17);

/// The middle action rides a looser spring, so it overshoots further than the
/// two either side of it and the three do not arrive as one rank.
const kFabLooseOpenSpring =
    SpringDescription(mass: 1, stiffness: 130, damping: 13);

const kFabActionStagger = Duration(milliseconds: 60);

/// The scrim behind an open button: a plain fade, no blur. Chrome that dims
/// the library still lets you read it, which is the point of leaving it there.
const kFabScrimFade = Duration(milliseconds: 200);

/// A pill only becomes real over the last part of its trip, so what leaves the
/// button is the goo and what arrives is the pill.
const kActionScaleInput = [0.6, 1.0];
const kActionScaleOutput = [0.4, 1.0];
const kActionOpacityInput = [0.65, 1.0];
const kActionOpacityOutput = [0.0, 1.0];

/// Maps [value] from [inputRange] to [outputRange], clamped at both ends.
double interpolateClamped(
  double value,
  List<double> inputRange,
  List<double> outputRange,
) {
  final t = ((value - inputRange[0]) / (inputRange[1] - inputRange[0]))
      .clamp(0.0, 1.0);
  return outputRange[0] + (outputRange[1] - outputRange[0]) * t;
}
