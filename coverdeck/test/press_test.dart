import 'package:coverdeck/app.dart';
import 'package:coverdeck/painting/glyphs.dart';
import 'package:coverdeck/widgets/glyph_icon.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

Finder _play() => find.byWidgetPredicate(
  (widget) => widget is GlyphIcon && widget.glyph == Glyph.playFill,
);

void main() {
  group('a held control springs inward', () {
    for (final ms in const [0, 100, 250]) {
      testWidgets('$ms ms into the press', (tester) async {
        await pumpScreen(tester, const App());
        final gesture = await tester.startGesture(tester.getCenter(_play()));
        await tester.pump();
        if (ms > 0) {
          await pumpMs(tester, ms);
        }
        await capture(tester, 'press__t${ms.toString().padLeft(4, '0')}');
        await gesture.cancel();
        await settle(tester);
      });
    }

    testWidgets('and springs back when the touch is lost', (tester) async {
      await pumpScreen(tester, const App());
      final before = tester.getRect(_play());
      final gesture = await tester.startGesture(tester.getCenter(_play()));
      await tester.pump();
      await pumpMs(tester, 250);
      final held = tester.getRect(_play());
      expect(held.width, lessThan(before.width * 0.9));
      await gesture.cancel();
      await settle(tester);
      expect(tester.getRect(_play()).width, closeTo(before.width, 0.01));
    });
  });
}
