import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/data/fixtures.dart';
import 'package:crypto_wallet/widgets/shimmer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/golden.dart';
import 'support/pump.dart';

void main() {
  testWidgets('receive skeleton while loading', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.receive));
    // The eyebrow placeholder keeps its 128 px width inside the stretched column.
    final shimmers = find.byType(Shimmer);
    expect(
      shimmers.evaluate().map(
        (e) => tester.getSize(find.byWidget(e.widget)).width,
      ),
      contains(128.0),
    );
    await capture(tester, 'receive__loading');
  });

  testWidgets('receive default', (tester) async {
    await pumpScreen(tester, const App(initialRoute: Routes.receive));
    // 900 ms of loading, then the cards settle and the QR sweep completes.
    await pumpFor(tester, 3400);
    expect(find.text('Your Ethereum address'), findsOneWidget);
    expect(find.text('Copy Address'), findsOneWidget);
    await capture(tester, 'receive__default');
  });

  test('the QR payload is the network address at level M', () {
    final code = QrCode.fromData(
      data: networks[0].address,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final image = QrImage(code);
    // The 43-byte address at level M needs type 4 (33 modules), which is what
    // automatic sizing picks.
    expect(networks[0].address.length, 43);
    expect(image.moduleCount, 33);
    expect(image.isDark(0, 0), isTrue, reason: 'finder pattern corner');
  });
}
