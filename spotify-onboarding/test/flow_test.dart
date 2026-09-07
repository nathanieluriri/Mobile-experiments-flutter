import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/app.dart';
import 'package:spotify_onboarding/data/artists.dart';
import 'package:spotify_onboarding/screens/onboarding/connect_spotify_screen.dart';
import 'package:spotify_onboarding/widgets/card_marquee/card_marquee.dart';
import 'package:spotify_onboarding/widgets/icons/back_arrow_icon.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';
import 'package:spotify_onboarding/widgets/marquee_card.dart';

import 'support/golden.dart';
import 'support/marquee_offsets.dart';

/// Ids of the cards in the tree, top to bottom.
List<String> visibleIds(WidgetTester tester) => tester
    .widgetList<MarqueeCard>(find.byType(MarqueeCard))
    .map((card) => card.item.id)
    .toList();

void main() {
  testWidgets('the flow starts on find concerts', (tester) async {
    await pumpScreen(tester, const App());
    expect(find.text('Find Concerts'), findsOne);
    expect(find.textContaining('1 of 3', findRichText: true), findsOne);
  });

  testWidgets('skip moves on and back returns', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);
    expect(find.textContaining('2 of 3', findRichText: true), findsOne);

    await tester.tap(find.byType(BackArrowIcon));
    await tester.pumpAndSettle();
    expect(find.text('Find Concerts'), findsOne);
  });

  testWidgets('the connect step offers no way forward', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Enable Location'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect Spotify'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);
  });

  testWidgets('the marquee runs in order and never shows a seam', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: artistRestOffset);
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      hostApp(
        ConnectSpotifyScreen(onBack: noop, marqueeController: controller),
      ),
    );

    for (final offset in [
      artistRestOffset,
      artistRestOffset - kMarqueeItemHeight * 3.5,
      artistRestOffset - kMarqueeItemHeight * 8,
      artistRestOffset + kMarqueeItemHeight * 8,
      artistRestOffset + kMarqueeItemHeight * 61.5,
    ]) {
      controller.jumpTo(offset);
      await tester.pump();
      final ids = visibleIds(tester);
      expect(ids.length, greaterThan(4), reason: 'at offset $offset');
      final start = artists.indexWhere((item) => item.id == ids.first);
      for (var i = 0; i < ids.length; i++) {
        expect(
          ids[i],
          artists[(start + i) % artists.length].id,
          reason: 'at offset $offset, position $i',
        );
      }
    }
  });

  testWidgets('a flick always comes to rest on a card boundary', (
    tester,
  ) async {
    final controller = ScrollController(initialScrollOffset: artistRestOffset);
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      hostApp(
        ConnectSpotifyScreen(onBack: noop, marqueeController: controller),
      ),
    );

    for (final flick in [-320.0, -60.0, 45.0, 260.0]) {
      await tester.fling(find.byType(CardMarquee), Offset(0, flick), 700);
      await tester.pumpAndSettle();
      final slots = controller.offset / kMarqueeItemHeight;
      expect(slots, moreOrLessEquals(slots.roundToDouble(), epsilon: 0.01));
    }
  });

  testWidgets('cards sit where the layout constants put them', (tester) async {
    final controller = ScrollController(initialScrollOffset: artistRestOffset);
    addTearDown(controller.dispose);
    await pumpScreen(
      tester,
      hostApp(
        ConnectSpotifyScreen(onBack: noop, marqueeController: controller),
      ),
    );

    final viewport = tester.getRect(find.byType(CardMarquee));
    expect(viewport.top, 270);
    expect(viewport.bottom, 874);

    // A slot's middle sits half a slot below the scroll offset it starts at,
    // and the marquee opens with the sixth artist in the first whole slot. The
    // slot before that one is drawn too, so its lean can reach back into view.
    final cards = tester.widgetList<MarqueeCard>(find.byType(MarqueeCard));
    expect(cards.length, lessThan(artists.length));
    for (final card in cards) {
      final slot = artists.indexWhere((item) => item.id == card.item.id);
      var k = (slot - 5 + artists.length) % artists.length;
      if (k == artists.length - 1) {
        k = -1;
      }
      final expected =
          viewport.top + kMarqueeItemHeight / 2 + kMarqueeItemHeight * k;
      expect(
        tester.getRect(find.byWidget(card)).center.dy,
        moreOrLessEquals(expected, epsilon: 0.01),
        reason: card.item.id,
      );
    }
  });

  testWidgets('the back arrow stays solid while it is held', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(BackArrowIcon)),
    );
    addTearDown(() => gesture.up());
    await pumpMs(tester, 150);

    final dimmed = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.byType(BackArrowIcon),
            matching: find.byType(Opacity),
          ),
        )
        .where((layer) => layer.opacity < 1);
    expect(dimmed, isEmpty);
  });

  testWidgets('the header controls answer just outside their edges', (
    tester,
  ) async {
    await pumpScreen(tester, const App());

    // Five points left of the Skip pill.
    await tester.tapAt(const Offset(335, 84));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);

    // Eight points left of the back arrow's slot.
    await tester.tapAt(const Offset(8, 84));
    await tester.pumpAndSettle();
    expect(find.text('Find Concerts'), findsOne);

    // Four points past the right edge of the Skip pill.
    await tester.tapAt(const Offset(390, 84));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);

    // Four points below the Skip pill.
    await tester.tapAt(const Offset(360, 98));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);

    await tester.tap(find.byType(BackArrowIcon));
    await tester.pumpAndSettle();

    // Four points above the Skip pill.
    await tester.tapAt(const Offset(360, 70));
    await tester.pumpAndSettle();
    expect(find.text('Connect Your'), findsOne);
  });
}
