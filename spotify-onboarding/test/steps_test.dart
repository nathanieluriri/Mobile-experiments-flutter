import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';
import 'package:spotify_onboarding/screens/onboarding/find_concerts_screen.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

void main() {
  testWidgets('find concerts step at rest', (tester) async {
    await pumpScreen(tester, hostApp(const FindConcertsScreen()));
    await capture(tester, 'step1__default');
  });

  testWidgets('connect spotify step at rest', (tester) async {
    await pumpScreen(tester, hostApp(const ConnectSpotifyScreen(onBack: noop)));
    await capture(tester, 'step2__default');
  });
}
