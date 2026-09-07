import 'package:flutter_test/flutter_test.dart';
import 'package:gooey_fab/app.dart';
import 'package:gooey_fab/constants/gooey_fab.dart';
import 'package:gooey_fab/painting/feather_icons.dart';

import 'support/golden.dart';

/// Finds the button carrying [glyph].
Finder _glyph(FeatherGlyph glyph) =>
    find.byWidgetPredicate((widget) => widget is FeatherIcon && widget.glyph == glyph);

void main() {
  testWidgets('backdrop blurs and dims the list while open', (tester) async {
    await pumpScreen(tester, const App());

    await tester.tap(_glyph(FeatherGlyph.plus));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await capture(tester, 'backdrop__open');
  });

  test('the backdrop fades a full strength blur instead of growing one', () {
    final half = backdropFilterAt(0.5).toString();
    final full = backdropFilterAt(1).toString();

    // Blur first, at the same radius whatever the progress.
    expect(half, contains('blur($backdropBlurSigma, $backdropBlurSigma'));
    expect(full, contains('blur($backdropBlurSigma, $backdropBlurSigma'));
    expect(half.indexOf('blur'), lessThan(half.indexOf('ColorFilter')));

    // Only the filtered image's alpha follows the progress, so the untouched
    // screen shows through underneath and edges stay hard while they fade.
    expect(half, contains('0.5, 0.0]'));
    expect(full, contains('1.0, 0.0]'));
  });
}
