import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

void main() {
  testWidgets('cards blur and wash out at the bottom of the marquee', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: artistRestOffset);
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      hostApp(ConnectSpotifyScreen(onBack: noop, marqueeController: controller)),
    );
    await precacheAssets(tester, artists.map((item) => item.imageAsset));
    await capture(tester, 'fade__default');
  });
}
