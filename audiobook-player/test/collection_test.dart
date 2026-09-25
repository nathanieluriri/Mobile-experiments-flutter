import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

void main() {
  testWidgets('collection tab at rest', (tester) async {
    await pumpScreen(tester, bookApp(initialTab: 2));
    await capture(tester, 'collection__default');
  });
}
