import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/data/fixtures.dart';
import 'package:crypto_wallet/data/models.dart';
import 'package:crypto_wallet/screens/ipo/allocation_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';
import 'support/pump.dart';

void main() {
  testWidgets('ipo skeleton while loading', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.ipo));
    await capture(tester, 'ipo__loading');
  });

  testWidgets('ipo default', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.ipo));
    // 1200 ms of loading, then the staggered cards settle.
    await pumpFor(tester, 4000);
    expect(find.text('NovaGrid'), findsOneWidget);
    expect(find.text('Subscribe to IPO'), findsOneWidget);
    // The header subtitle is centred on one line under the title.
    final subtitle = find.text(
      'Discover and invest in upcoming public offerings',
    );
    final title = find.text('IPO Market');
    expect(
      tester.getCenter(subtitle).dx,
      closeTo(tester.getCenter(title).dx, 1),
    );
    expect(tester.getSize(subtitle).height, lessThan(20));
    await capture(tester, 'ipo__default');
  });

  test('allocation estimate follows its formula', () {
    final estimate = computeAllocationEstimate(featuredIpo, 1000);
    // oversubscription 1.42, size pressure 0.036: (0.704 - 0.036) * 130 = 87.
    expect(estimate.allocationPercent, 87);
    expect(estimate.shares, 28);
    expect(estimate.totalUsd, closeTo(868, 1e-9));
    expect(estimate.tier, AllocationTier.high);
    expect(estimate.tierScore, 0.92);
    final big = computeAllocationEstimate(featuredIpo, 25000);
    expect(big.allocationPercent, 33);
    expect(big.tier, AllocationTier.low);
  });
}
