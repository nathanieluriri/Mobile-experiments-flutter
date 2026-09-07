import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/data/fixtures.dart';
import 'package:crypto_wallet/screens/swap/swap_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/pump.dart';

void main() {
  testWidgets('swap default', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.swap));
    await pumpFor(tester, 1500);
    expect(find.text('1 ETH = 2,437.52 USDC'), findsWidgets);
    await capture(tester, 'swap__default');
  });

  testWidgets('swap with a typed amount', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.swap));
    await pumpFor(tester, 1500);
    await tester.tap(keypadKey('0'));
    await pumpFor(tester, 100);
    await tester.tap(keypadKey('.'));
    await pumpFor(tester, 100);
    await tester.tap(keypadKey('1'));
    await pumpFor(tester, 1200);
    expect(find.text('Swap'), findsWidgets);
    await capture(tester, 'swap__amount');
  });

  test('quote and venue follow the source formulas', () {
    final quote = computeSwapQuote(tokens[0], tokens[1], 0.1);
    expect(quote.rate, closeTo(2437.52, 1e-9));
    expect(quote.toAmount, closeTo(243.752, 1e-9));
    expect(quote.feeUsd, closeTo(0.60938, 1e-5));
    expect(quote.priceImpact, closeTo(0.04 + 243.752 / 250000, 1e-9));
    expect(quote.networkFeeUsd, 1.84);
    expect(quote.minReceived, closeTo(243.752 * 0.995, 1e-9));
    expect(resolveSwapVenue(tokens[0], tokens[3]).label, 'Jupiter');
    expect(resolveSwapVenue(tokens[0], tokens[1]).label, 'Uniswap');
  });
}
