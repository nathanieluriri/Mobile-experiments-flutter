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
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key} opens',
      );
      await tester.tap(find.byIcon(LucideIcons.chevronLeft));
      await pumpFor(tester, 900);
      expect(
        find.text(entry.value),
        findsNothing,
        reason: '${entry.key} closes',
      );
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

  testWidgets('a closing flow settles on a fresh spring', (tester) async {
    await pumpScreen(tester, const App());
    await tester.tap(find.text('IPO'));
    await pumpFor(tester, 900);
    final open = tester.getTopLeft(find.text('IPO Market')).dy;
    final walletReceded = tester.getTopLeft(find.text('Total Balance')).dy;

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    // One frame starts the transition, then 120 ms into it.
    await tester.pump();
    await pumpMs(tester, 120);

    // A spring of mass 1, stiffness 280 and damping 30 released from rest
    // covers 63.6 percent of its travel in the first 120 ms and 96.1 percent
    // by 250 ms. Replaying the opening curve backwards would instead leave
    // the sheet almost still here and rush the last stretch.
    final travelled = tester.getTopLeft(find.text('IPO Market')).dy - open;
    expect(travelled / 874, closeTo(0.636, 0.03));

    // The wallet grows back on the same profile, so it has already started
    // returning toward its resting size.
    final wallet = tester.getTopLeft(find.text('Total Balance')).dy;
    expect(wallet, lessThan(walletReceded));

    await capture(tester, 'flow__closing_t0120');

    // Second point on the same spring, 250 ms in.
    await pumpMs(tester, 130);
    final settling = tester.getTopLeft(find.text('IPO Market')).dy - open;
    expect(settling / 874, closeTo(0.961, 0.03));
  });
}
