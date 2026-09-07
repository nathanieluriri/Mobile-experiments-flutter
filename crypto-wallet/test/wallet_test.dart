import 'package:crypto_wallet/app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('wallet at rest', (tester) async {
    await pumpScreen(tester, const App());
    await capture(tester, 'wallet__default');
  });
}
