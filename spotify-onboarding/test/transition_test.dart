import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/app.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/data/cities.dart';

import 'support/golden.dart';

void main() {
  testWidgets('a step hands over to the next', (tester) async {
    await pumpScreen(tester, const App());
    await precacheAssets(tester, [
      for (final item in [...cities, ...artists]) item.imageAsset,
    ]);

    await tester.tap(find.text('Enable Location'));
    await tester.pump();
    await capture(tester, 'handover__t0000');
    await pumpMs(tester, 150);
    await capture(tester, 'handover__t0150');
    await pumpMs(tester, 150);
    await capture(tester, 'handover__t0300');
    await pumpMs(tester, 150);
    await capture(tester, 'handover__t0450');
    await tester.pumpAndSettle();
    await capture(tester, 'handover__t0600');

    expect(find.text('Connect Your'), findsOne);
  });

  testWidgets('going back drifts the other way', (tester) async {
    await pumpScreen(tester, const App());
    await precacheAssets(tester, [
      for (final item in [...cities, ...artists]) item.imageAsset,
    ]);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // The back arrow, at the left of the header.
    await tester.tapAt(const Offset(27, 84));
    await tester.pump();
    await pumpMs(tester, 300);
    await capture(tester, 'handover__reverse');

    await tester.pumpAndSettle();
    expect(find.text('Find Concerts'), findsOne);
  });

  testWidgets('both steps stay put while the other is handed over', (
    tester,
  ) async {
    await pumpScreen(tester, const App());

    await tester.tap(find.text('Enable Location'));
    await tester.pump();
    // Both are on screen at once, the arriving one over the leaving one.
    expect(find.text('Find Concerts'), findsOne);
    expect(find.text('Connect Your'), findsOne);

    await pumpMs(tester, 300);
    expect(find.text('Find Concerts'), findsOne);

    await tester.pumpAndSettle();
    expect(find.text('Find Concerts'), findsNothing);
    expect(find.text('Connect Your'), findsOne);
  });

  testWidgets('a tap during the handover is ignored', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Enable Location'));
    await pumpMs(tester, 200);

    // The leaving step is still drawn but no longer answers.
    await tester.tapAt(const Offset(201, 804));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);
  });
}
