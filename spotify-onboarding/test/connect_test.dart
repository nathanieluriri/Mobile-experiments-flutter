import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/app.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

void main() {
  testWidgets('connect button dims while it is held', (tester) async {
    await pumpScreen(tester, hostApp(const ConnectSpotifyScreen(onBack: noop)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Connect Spotify')),
    );
    addTearDown(() => gesture.up());
    await pumpMs(tester, 150);
    await capture(tester, 'connect__pressed');
  });

  testWidgets('enabling location lands on the connect step', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Enable Location'));
    await tester.pumpAndSettle();
    await precacheImages(tester);
    await capture(tester, 'connect__done');
  });
}
