import 'package:audiobook_player/data/now_playing.dart';
import 'package:audiobook_player/state/player_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

/// Half of the distance it takes to drag the sheet all the way open on this
/// phone: 956 - 76 mini - (56 tab bar + 34 home indicator).
const _halfDrag = 395.0;

/// Somewhere on the mini player that is not the transport button.
const _grip = Offset(180, 830);

Future<void> _openByTap(WidgetTester tester) async {
  await tester.tap(find.text(nowPlayingTrack.title).first);
  await tester.pump();
}

void main() {
  testWidgets('sheet at the moment it is asked to open', (tester) async {
    await pumpScreen(tester, bookApp());
    await _openByTap(tester);
    await capture(tester, 'sheet__t0000');
  });

  testWidgets('sheet 150 ms into the spring', (tester) async {
    await pumpScreen(tester, bookApp());
    await _openByTap(tester);
    await pumpMs(tester, 150);
    await capture(tester, 'sheet__t0150');
  });

  testWidgets('sheet 300 ms into the spring', (tester) async {
    await pumpScreen(tester, bookApp());
    await _openByTap(tester);
    await pumpMs(tester, 300);
    await capture(tester, 'sheet__t0300');
  });

  testWidgets('sheet settled open', (tester) async {
    await pumpScreen(tester, bookApp());
    await _openByTap(tester);
    await pumpMs(tester, 1500);
    await capture(tester, 'sheet__open');
  });

  testWidgets('sheet open at the start of the track, as the app opens it', (
    tester,
  ) async {
    await pumpScreen(tester, bookApp(start: const PlayerStart()));
    await _openByTap(tester);
    await pumpMs(tester, 1500);
    await capture(tester, 'sheet__open_at_start');
  });

  testWidgets('sheet held half way up a drag', (tester) async {
    await pumpScreen(tester, bookApp());
    final gesture = await tester.startGesture(
      _grip,
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(0, -_halfDrag));
    await tester.pump();
    await capture(tester, 'sheet__drag_half');
    await gesture.up();
    await tester.pump();
  });
}
