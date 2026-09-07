import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/app.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/golden.dart';

void main() {
  testWidgets('backdrop blurs and dims the list while open', (tester) async {
    await pumpScreen(tester, const App());

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await capture(tester, 'backdrop__open');
  });
}
