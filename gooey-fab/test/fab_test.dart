import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/app.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/golden.dart';

void main() {
  testWidgets('opening keyframes', (tester) async {
    await pumpScreen(tester, const App());

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await capture(tester, 'fab__t0000');

    await pumpMs(tester, 100);
    await capture(tester, 'fab__t0100');

    await pumpMs(tester, 70);
    await capture(tester, 'fab__t0170');

    await pumpMs(tester, 50);
    await capture(tester, 'fab__t0220');

    await pumpMs(tester, 380);
    await capture(tester, 'fab__t0600');
  });

  testWidgets('closing keyframe', (tester) async {
    await pumpScreen(tester, const App());

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    await pumpMs(tester, 300);
    await capture(tester, 'fab_close__t0300');
  });
}
