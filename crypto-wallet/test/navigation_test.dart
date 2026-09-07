import 'package:crypto_wallet/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'scramble_test.dart' show pullToRefresh;
import 'support/golden.dart';
import 'support/pump.dart';

void main() {
  testWidgets('refresh, then open every flow and come back', (tester) async {
    await pumpScreen(tester, const App());
    await pullToRefresh(tester);
    await pumpFor(tester, 3000);
    expect(find.text('Total Balance'), findsOneWidget);

    const flows = {
      'IPO': 'IPO Market',
      'Send': 'Send crypto securely',
      'Receive': 'Receive crypto instantly',
      'Swap': 'Exchange assets instantly',
    };
    for (final entry in flows.entries) {
      await tester.tap(find.text(entry.key));
      await pumpFor(tester, 900);
      expect(find.text(entry.value), findsOneWidget, reason: '${entry.key} opens');
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await pumpFor(tester, 900);
      expect(find.text(entry.value), findsNothing, reason: '${entry.key} closes');
      expect(find.text('Total Balance'), findsOneWidget);
    }
  });

  testWidgets('the wallet recedes behind an opening flow', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('IPO'));
    // One frame starts the transition, then 120 ms into it.
    await tester.pump();
    await pumpMs(tester, 120);
    // The wallet has shrunk: its top-left corner is inside the screen.
    final wallet = tester.getTopLeft(find.text('Total Balance'));
    expect(wallet.dy, greaterThan(62 + 16 + 48 + 24 + 8));
    expect(find.text('IPO Market'), findsOneWidget);
    await capture(tester, 'flow__opening_t0120');
  });
}
