/// Height of one slot in the marquee. Cards are shorter than this, so the
/// difference is the gap between them.
const kMarqueeItemHeight = 124.0;

/// Radius of the imagined cylinder the cards are wrapped around. A card leaning
/// by `tilt` slides left by `kArcRadius * (1 - cos tilt)`, which is how far its
/// centre would have travelled around the cylinder.
const kArcRadius = 520.0;

/// Lean, in degrees, of a card sitting a full half viewport from the centre.
const kMaxTiltDeg = 14.0;

/// How much of a card's own tilt is added to the lean the arc gives it.
const kItemTiltInfluence = 0.2;

/// A card at the clamp is drawn at `1 - kMaxScaleShrink` of its size.
const kMaxScaleShrink = 0.12;

/// Distance from the centre, in half viewports, past which scale stops
/// shrinking.
const kCenterDistanceClamp = 1.2;

/// Height of the white gradient at the top of the marquee.
const kTopFadeHeight = 96.0;

/// Height of the blurred band at the bottom of the marquee.
const kBottomFadeHeight = 160.0;

/// Height of the white gradient inside the blurred band.
const kBottomGradientHeight = 56.0;
