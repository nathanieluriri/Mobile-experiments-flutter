import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

/// Speed of the flick the keyframes are measured from, in pixels per second.
/// It coasts about 90 px, which rounds up to one whole slot.
const _flickVelocity = 900.0;

void main() {
  testWidgets('a flick coasts and settles on a card boundary', (tester) async {
    final controller = ScrollController(initialScrollOffset: artistRestOffset);
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      hostApp(ConnectSpotifyScreen(marqueeController: controller)),
    );
    await precacheAssets(tester, artists.map((item) => item.imageAsset));

    final position = controller.position as ScrollPositionWithSingleContext;
    position.goBallistic(_flickVelocity);

    await tester.pump();
    await capture(tester, 'marquee__t0000');
    await pumpMs(tester, 300);
    await capture(tester, 'marquee__t0300');
    await pumpMs(tester, 400);
    await capture(tester, 'marquee__t0700');
    await tester.pumpAndSettle();
    await capture(tester, 'marquee__snapped');

    expect(
      controller.offset,
      moreOrLessEquals(artistRestOffset + kMarqueeItemHeight, epsilon: 0.5),
    );
  });
}
