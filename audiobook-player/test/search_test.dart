import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

void main() {
  testWidgets('search tab at rest', (tester) async {
    await pumpScreen(tester, bookApp(initialTab: 1));
    await capture(tester, 'search__default');
  });
}
