import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/app.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';
import 'package:spotify_onboarding/screens/onboarding/find_concerts_screen.dart';
import 'package:spotify_onboarding/screens/onboarding/onboarding_step_layout.dart';
import 'package:spotify_onboarding/theme/colors.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

/// The ground the step layout is painted on.
Color groundOf(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(
            of: find.byType(OnboardingStepLayout),
            matching: find.byType(Material),
          )
          .first,
    )
    .color!;

void main() {
  testWidgets('find concerts step on the dark ground', (tester) async {
    useDarkGround(tester);
    await pumpScreen(tester, hostApp(const FindConcertsScreen()));
    await capture(tester, 'step1__dark');
  });

  testWidgets('connect spotify step on the dark ground', (tester) async {
    useDarkGround(tester);
    await pumpScreen(tester, hostApp(const ConnectSpotifyScreen(onBack: noop)));
    await capture(tester, 'step2__dark');
  });

  testWidgets('the flow takes the ground the device is set to', (tester) async {
    await pumpScreen(tester, const App());
    expect(groundOf(tester), AppColors.white);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(groundOf(tester), AppColors.pitch);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(groundOf(tester), AppColors.white);
  });

  testWidgets('the button swaps its slab and its label with the ground', (
    tester,
  ) async {
    Color slabOf(WidgetTester tester) => (tester
                .widget<Container>(
                  find.ancestor(
                    of: find.text('Connect Spotify'),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration)
        .color!;
    Color labelOf(WidgetTester tester) =>
        tester.widget<Text>(find.text('Connect Spotify')).style!.color!;

    await pumpScreen(tester, hostApp(const ConnectSpotifyScreen(onBack: noop)));
    expect(slabOf(tester), AppColors.ink);
    expect(labelOf(tester), AppColors.spotify);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(slabOf(tester), AppColors.spotify);
    expect(labelOf(tester), AppColors.ink);
  });

  testWidgets('the marquee fades into the dark ground, not into white', (
    tester,
  ) async {
    useDarkGround(tester);
    await pumpScreen(
      tester,
      hostApp(const ConnectSpotifyScreen(onBack: noop)),
    );
    await precacheAssets(tester, artists.map((item) => item.imageAsset));
    await capture(tester, 'fade__dark');
  });
}
