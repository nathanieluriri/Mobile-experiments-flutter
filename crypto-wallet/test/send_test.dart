import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/pump.dart';

void main() {
  testWidgets('send default', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.send));
    await pumpFor(tester, 1500);
    expect(find.text('Paste or scan wallet address'), findsOneWidget);
    // The fee card is on screen at rest: the amount block yields, not the cards.
    expect(find.text('ARRIVAL'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('ARRIVAL')).dy, lessThan(874 - 34));
    // All five recents fit on screen.
    expect(tester.getTopRight(find.text('Vault')).dx, lessThan(402));
    await capture(tester, 'send__default');
  });

  testWidgets('send with a typed amount', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.send));
    await pumpFor(tester, 1500);
    await tester.tap(keypadKey('2'));
    await pumpFor(tester, 120);
    await tester.tap(keypadKey('5'));
    await pumpFor(tester, 120);
    await tester.tap(keypadKey('0'));
    await pumpFor(tester, 1200);
    await capture(tester, 'send__amount');
  });

  test('amount keys follow the source rules', () {
    expect(appendAmountKey('', '.'), '0.');
    expect(appendAmountKey('0', '5'), '5');
    expect(appendAmountKey('12.34', '5'), '12.34');
    expect(appendAmountKey('123456789', '1'), '123456789');
    expect(deleteAmountKey('1'), '');
    expect(deleteAmountKey('12'), '1');
    expect(groupThousands('1234567.5'), '1,234,567.5');
    expect(truncateAddress('0x7f4E2aC8b1e94dD7f21A6c09E14bD24c5a83f9c41'), '0x7f4E…9c41');
    expect(formatTokenAmount(250, 2437.52, 4), '0.1026');
  });
}
