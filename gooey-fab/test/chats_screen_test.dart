import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/app.dart';

import 'support/golden.dart';

void main() {
  testWidgets('chat list at rest', (tester) async {
    await pumpScreen(tester, const App());
    await capture(tester, 'chats__default');
  });
}
