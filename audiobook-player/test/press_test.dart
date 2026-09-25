import 'package:audiobook_player/screens/playlists/playlist_row.dart';
import 'package:audiobook_player/widgets/play_pause_button.dart';
import 'package:audiobook_player/widgets/story_card.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

double opacityUnder(WidgetTester tester, Finder ancestor) {
  final finder = find.descendant(of: ancestor, matching: find.byType(Opacity));
  return tester.widget<Opacity>(finder.first).opacity;
}

/// The transport disc on the first playlist row.
const _rowDisc = Offset(380, 181);

void main() {
  testWidgets('a card dims while it is held and comes back on release', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final card = find.byType(StoryCard).first;
    expect(opacityUnder(tester, card), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(card),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(opacityUnder(tester, card), 0.85);

    await gesture.up();
    await tester.pump();
    expect(opacityUnder(tester, card), 1);
  });

  testWidgets('the dim shows straight away, not after the press deadline', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final card = find.byType(StoryCard).first;
    final gesture = await tester.startGesture(
      tester.getCenter(card),
      kind: PointerDeviceKind.touch,
    );
    // Well inside the deadline a competing tap recogniser would wait for.
    await pumpMs(tester, 16);
    expect(opacityUnder(tester, card), 0.85);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('scrolling away from a held card clears the dim', (tester) async {
    await pumpScreen(tester, bookApp());
    final card = find.byType(StoryCard).first;
    final gesture = await tester.startGesture(
      tester.getCenter(card),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(opacityUnder(tester, card), 0.85);

    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(opacityUnder(tester, card), 1);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('holding a disc inside a row dims the disc and not the row', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp(initialTab: 3));
    final row = find.byType(PlaylistRow).first;
    final disc = find.descendant(
      of: row,
      matching: find.byType(PlayPauseButton),
    );

    final gesture = await tester.startGesture(
      _rowDisc,
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(opacityUnder(tester, disc), 0.8);
    expect(opacityUnder(tester, row), 1);

    await gesture.up();
    await tester.pump();
    expect(opacityUnder(tester, disc), 1);
    expect(opacityUnder(tester, row), 1);
  });

  testWidgets('holding a row away from the disc dims the row', (tester) async {
    await pumpScreen(tester, bookApp(initialTab: 3));
    final row = find.byType(PlaylistRow).first;
    final gesture = await tester.startGesture(
      const Offset(200, 181),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(opacityUnder(tester, row), 0.85);
    await gesture.up();
    await tester.pump();
    expect(opacityUnder(tester, row), 1);
  });
}
