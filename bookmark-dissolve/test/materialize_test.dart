import 'package:bookmark_dissolve/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board.dart';
import 'support/golden.dart';

void main() {
  testWidgets('the dust gathers back into cards', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await startRestore(tester);

    await capture(tester, 'materialize__t0000');
    await runMs(tester, 400);
    await capture(tester, 'materialize__t0400');
    await runMs(tester, 800);
    await capture(tester, 'materialize__t1200');
  });

  testWidgets('the cards come back one after another', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await startRestore(tester);

    // The first card is back after its 1200 ms run, the others follow at 140 ms
    // apart, so at that moment only one has finished.
    await runMs(tester, 1210);
    expect(isRunning(tester), isTrue);
    await runMs(tester, 400);
    expect(isRunning(tester), isFalse);
  });

  testWidgets('every card is on the board once it has restored', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await startRestore(tester);
    await tester.pumpAndSettle();

    for (final title in const [kMymind, kPlay, kArc, kNotion]) {
      expect(cardNamed(title), findsOneWidget);
    }
    await capture(tester, 'board__restored');
  });
}
