import 'package:audiobook_player/data/now_playing.dart';
import 'package:audiobook_player/home_shell.dart';
import 'package:audiobook_player/state/player_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

const _grip = Offset(180, 830);
const _openGrip = Offset(220, 300);

PlayerController playerOf(WidgetTester tester) =>
    tester.state<HomeShellState>(find.byType(HomeShell)).player;

Future<void> settle(WidgetTester tester) async {
  await pumpMs(tester, 16);
  await pumpMs(tester, 2000);
}

void main() {
  testWidgets('tapping the mini row opens the sheet', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    expect(player.sheetProgress.value, 0);
    await tester.tap(find.text(nowPlayingTrack.title).first);
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(1, 0.001));
  });

  testWidgets('the handle shuts an open sheet and opens a shut one', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    player.sheetProgress.value = 1;
    await tester.pump();
    await tester.tapAt(const Offset(220, 74));
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(0, 0.001));
  });

  testWidgets('a drag maps travel onto progress one for one', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, -395));
    await tester.pump();
    expect(player.sheetProgress.value, closeTo(0.5, 0.001));
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(player.sheetProgress.value, closeTo(0.2468, 0.001));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a drag never pushes progress outside 0 to 1', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, -2000));
    await tester.pump();
    expect(player.sheetProgress.value, 1);
    await gesture.moveBy(const Offset(0, 4000));
    await tester.pump();
    expect(player.sheetProgress.value, 0);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('taking hold of the sheet interrupts the settle spring', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    await tester.tap(find.text(nowPlayingTrack.title).first);
    await tester.pump();
    await pumpMs(tester, 80);
    final caught = player.sheetProgress.value;
    expect(caught, greaterThan(0.1));
    expect(caught, lessThan(0.95));

    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, 79));
    await tester.pump();
    expect(player.sheetProgress.value, closeTo(caught - 0.1, 0.001));

    // The spring is not still running underneath the finger.
    await pumpMs(tester, 200);
    expect(player.sheetProgress.value, closeTo(caught - 0.1, 0.001));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a flick down dismisses even from above the middle', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    player.sheetProgress.value = 1;
    await tester.pump();
    await tester.flingFrom(_openGrip, const Offset(0, 120), 1400);
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(0, 0.001));
  });

  testWidgets('a flick up opens even from below the middle', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    await tester.flingFrom(_grip, const Offset(0, -160), 1500);
    expect(player.sheetProgress.value, lessThan(0.5));
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(1, 0.001));
  });

  testWidgets('letting go below the middle without a flick shuts it', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(0, 0.001));
  });

  testWidgets('the handle opens a shut sheet', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    await tester.tapAt(const Offset(220, 800));
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(1, 0.001));
  });

  testWidgets('a flick is what decides it, either side of 500 a second', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);

    Future<double> release(double from, double velocity) async {
      player.sheetProgress.value = from;
      player.onDragEnd(velocity);
      await settle(tester);
      return player.sheetProgress.value;
    }

    // Above the middle it opens unless the flick is downward and hard enough.
    expect(await release(0.6, 499), closeTo(1, 0.001));
    expect(await release(0.6, 501), closeTo(0, 0.001));
    // Below the middle it shuts unless the flick is upward and hard enough.
    expect(await release(0.4, -499), closeTo(0, 0.001));
    expect(await release(0.4, -501), closeTo(1, 0.001));
  });

  testWidgets('the sheet starts following the finger after 12 pixels', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, -11));
    await tester.pump();
    expect(player.sheetProgress.value, 0);
    await gesture.moveBy(const Offset(0, -2));
    await tester.pump();
    expect(player.sheetProgress.value, closeTo(13 / 790, 0.0001));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('the transport starts and stops the track', (tester) async {
    await pumpScreen(tester, bookApp());
    final player = playerOf(tester);
    expect(player.isPlaying, isFalse);
    expect(player.playbackPosition.isAnimating, isFalse);
    await tester.tapAt(const Offset(401, 828));
    await tester.pump();
    expect(player.isPlaying, isTrue);
    expect(player.playbackPosition.isAnimating, isTrue);
    await tester.tapAt(const Offset(401, 828));
    await tester.pump();
    expect(player.isPlaying, isFalse);
    expect(player.playbackPosition.isAnimating, isFalse);
  });

  testWidgets('the tabs switch while the sheet is shut', (tester) async {
    await pumpScreen(tester, bookApp());
    expect(find.text('Trending'), findsOneWidget);
    for (final tab in ['Search', 'Collection', 'Playlist']) {
      await tester.tap(find.text(tab));
      await tester.pump();
    }
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('New playlist'), findsOneWidget);
    await tester.tap(find.text('Stories'));
    await tester.pump();
    expect(find.text('Trending'), findsOneWidget);
  });

  testWidgets('a playlist row opens the player', (tester) async {
    await pumpScreen(tester, bookApp(initialTab: 3));
    final player = playerOf(tester);
    await tester.tapAt(const Offset(380, 181));
    await settle(tester);
    expect(player.sheetProgress.value, closeTo(1, 0.001));
  });

  testWidgets('the track runs on from where it was left', (tester) async {
    await pumpScreen(
      tester,
      bookApp(start: const PlayerStart(positionSeconds: 148, isPlaying: true)),
    );
    final player = playerOf(tester);
    final from = player.positionSeconds;
    expect(from, greaterThanOrEqualTo(148));
    await pumpMs(tester, 4000);
    expect(player.positionSeconds, closeTo(from + 4, 0.05));
  });
}
