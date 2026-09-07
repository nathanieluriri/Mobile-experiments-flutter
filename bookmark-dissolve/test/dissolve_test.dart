import 'package:bookmark_dissolve/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board.dart';
import 'support/golden.dart';

void main() {
  testWidgets('a card comes apart over three seconds', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    // Arc is deleted first, so the Play card comes apart from a board holding
    // two cards, the way the recording shows it.
    await removeCard(tester, kArc);

    await startDissolve(tester, kPlay);
    await capture(tester, 'dissolve__t0000');
    await pumpMs(tester, 300);
    await capture(tester, 'dissolve__t0300');
    await pumpMs(tester, 600);
    await capture(tester, 'dissolve__t0900');
    await pumpMs(tester, 900);
    await capture(tester, 'dissolve__t1800');
    await pumpMs(tester, 1000);
    await capture(tester, 'dissolve__t2800');
  });

  testWidgets('the card lower in a column comes apart the same way', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();

    await startDissolve(tester, kArc);
    await pumpMs(tester, 900);
    await capture(tester, 'dissolve_arc__t0900');
    await pumpMs(tester, 900);
    await capture(tester, 'dissolve_arc__t1800');
    await pumpMs(tester, 1000);
    await capture(tester, 'dissolve_arc__t2800');
  });

  testWidgets('the card keeps its slot until the run ends', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    final before = tester.getRect(cardNamed(kMymind));

    await startDissolve(tester, kArc);
    await pumpMs(tester, 2900);
    // Arc is still mounted and invisible, holding its place in the column.
    expect(cardNamed(kArc), findsOneWidget);
    expect(tester.getRect(cardNamed(kMymind)), before);

    await pumpMs(tester, 200);
    expect(cardNamed(kArc), findsNothing);
  });
}
