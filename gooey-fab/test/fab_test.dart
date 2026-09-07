import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/app.dart';
import 'package:gooey_fab/painting/feather_icons.dart';

import 'support/golden.dart';

/// Finds the button carrying [glyph].
Finder _glyph(FeatherGlyph glyph) =>
    find.byWidgetPredicate((widget) => widget is FeatherIcon && widget.glyph == glyph);

void main() {
  testWidgets('opening keyframes', (tester) async {
    await pumpScreen(tester, const App());

    await tester.tap(_glyph(FeatherGlyph.plus));
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

    await tester.tap(_glyph(FeatherGlyph.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(_glyph(FeatherGlyph.plus));
    await tester.pump();
    await pumpMs(tester, 300);
    await capture(tester, 'fab_close__t0300');
  });
}
