import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

/// A harder flick, for the rest it comes to two boundaries further on.
const _hardFlickVelocity = 2600.0;

Future<ScrollPositionWithSingleContext> _open(WidgetTester tester) async {
  final controller = ScrollController(initialScrollOffset: artistFlickOffset);
  addTearDown(controller.dispose);
  await pumpScreen(
    tester,
    hostApp(ConnectSpotifyScreen(onBack: noop, marqueeController: controller)),
  );
  await precacheAssets(tester, artists.map((item) => item.imageAsset));
  return controller.position as ScrollPositionWithSingleContext;
}

void main() {
  testWidgets('a flick coasts and settles on a card boundary', (tester) async {
    final position = await _open(tester);
    position.goBallistic(artistFlickVelocity);

    await tester.pump();
    await capture(tester, 'marquee__t0000');
    await pumpMs(tester, 300);
    await capture(tester, 'marquee__t0300');
    await pumpMs(tester, 400);
    await capture(tester, 'marquee__t0700');

    // Let go a third of a slot past a boundary, it coasts to the next one.
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      moreOrLessEquals(artistRestOffset + 2 * kMarqueeItemHeight, epsilon: 0.5),
    );

    // A harder flick carries it two boundaries further and it settles again.
    position.goBallistic(_hardFlickVelocity);
    await tester.pumpAndSettle();
    await capture(tester, 'marquee__snapped');
    expect(
      position.pixels,
      moreOrLessEquals(artistRestOffset + 4 * kMarqueeItemHeight, epsilon: 0.5),
    );
  });

  testWidgets('the four captured offsets are four different pictures', (
    tester,
  ) async {
    final position = await _open(tester);
    position.goBallistic(artistFlickVelocity);
    await tester.pump();

    final seen = <double>[position.pixels];
    await pumpMs(tester, 300);
    seen.add(position.pixels);
    await pumpMs(tester, 400);
    seen.add(position.pixels);
    await tester.pumpAndSettle();
    position.goBallistic(_hardFlickVelocity);
    await tester.pumpAndSettle();
    seen.add(position.pixels);

    for (var i = 1; i < seen.length; i++) {
      expect(
        seen[i] - seen[i - 1],
        greaterThan(1),
        reason: 'offset $i repeats offset ${i - 1} at ${seen[i]}',
      );
    }
    // The flick is let go mid slot, so the first frame is already in motion.
    expect(seen.first % kMarqueeItemHeight, greaterThan(1));
  });
}
