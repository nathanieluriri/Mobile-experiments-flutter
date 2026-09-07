import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

void main() {
  testWidgets('stories tab at rest', (tester) async {
    await pumpScreen(tester, bookApp());
    await capture(tester, 'stories__default');
  });
}
