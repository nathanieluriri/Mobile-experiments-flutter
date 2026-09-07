import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/widgets/card_marquee/card_marquee.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';

/// Where the marquee sits at rest in the recorded run of the flow: five slots
/// past the one it opens on, so Sigur Ros is clipped at the top and Tame Impala
/// leads.
final artistRestOffset = marqueeOrigin(artists.length) + 5 * kMarqueeItemHeight;

/// Where the recorded flick was let go: a third of a slot past the boundary
/// after the rest state, still moving.
final artistFlickOffset = artistRestOffset + 1.33 * kMarqueeItemHeight;

/// Speed the recorded flick was let go at, in pixels per second. It coasts
/// about 85 px, which carries the marquee to the next boundary.
const artistFlickVelocity = 850.0;

/// A no-op for a callback the flow always supplies but a still picture cannot
/// act on.
void noop() {}
