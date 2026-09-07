import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/widgets/card_marquee/card_marquee.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';

/// Where the marquee sits in the recorded run of the flow: five slots past the
/// one it opens on, so Sigur Ros is clipped at the top and Tame Impala leads.
final artistRestOffset =
    marqueeOrigin(artists.length) + 5 * kMarqueeItemHeight;
