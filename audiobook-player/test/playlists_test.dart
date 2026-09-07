import 'package:flutter_test/flutter_test.dart';

import 'support/app.dart';
import 'support/golden.dart';

void main() {
  testWidgets('playlists tab at rest', (tester) async {
    await pumpScreen(tester, bookApp(initialTab: 3));
    await capture(tester, 'playlists__default');
  });
}
