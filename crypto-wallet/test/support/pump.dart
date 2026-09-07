import 'package:crypto_wallet/widgets/numeric_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Advances the clock by [ms] in small [step]s so animations that start from
/// timers pick up their first frame close to the moment they were scheduled.
Future<void> pumpFor(WidgetTester tester, int ms, {int step = 32}) async {
  var remaining = ms;
  while (remaining > 0) {
    final slice = remaining < step ? remaining : step;
    await tester.pump(Duration(milliseconds: slice));
    remaining -= slice;
  }
}

/// The keypad key showing [label].
Finder keypadKey(String label) {
  return find.descendant(of: find.byType(NumericKeyboard), matching: find.text(label));
}
