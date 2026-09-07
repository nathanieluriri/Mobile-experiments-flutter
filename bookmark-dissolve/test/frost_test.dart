import 'package:bookmark_dissolve/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board.dart';
import 'support/golden.dart';

void main() {
  testWidgets('the frost is deep while the card is still whole', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pumpAndSettle();
    await removeCard(tester, kArc);

    await startDissolve(tester, kPlay);
    await pumpMs(tester, 250);
    await capture(tester, 'frost__t0250');
  });
}
