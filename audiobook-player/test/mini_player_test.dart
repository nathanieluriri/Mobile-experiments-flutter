import 'package:audiobook_player/state/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

void main() {
  testWidgets('mini player stopped', (tester) async {
    await pumpScreen(tester, bookApp());
    await capture(tester, 'mini__default');
  });

  testWidgets('mini player running', (tester) async {
    await pumpScreen(
      tester,
      bookApp(start: const PlayerStart(positionSeconds: 148, isPlaying: true)),
    );
    await capture(tester, 'mini__playing');
  });
}
