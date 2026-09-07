import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  testWidgets('wallet at rest', (tester) async {
    await pumpScreen(tester, const App());
    await capture(tester, 'wallet__default');
  });

  testWidgets('text keeps its natural metrics inside Material', (tester) async {
    await pumpScreen(tester, const App());
    // Inter's natural line height is about 1.21 em. If the Material body
    // style leaked in, this label would be 15 * 1.43 tall instead.
    final label = tester.getSize(find.text('Total Balance'));
    expect(label.height, closeTo(15 * 1.21, 0.5));
    expect(text(15).inherit, isFalse);
    expect(text(15).letterSpacing, 0);
    // The amount baseline sits at 96 within the 158 px balance block:
    // safe area 62 + top pad 16 + header 48 + gap 24 + 96.
    final digit = find.text('2').first;
    final style = tester.widget<Text>(digit).style!;
    final painter = TextPainter(
      text: TextSpan(text: '2', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final top = tester.getTopLeft(digit).dy;
    expect(top + baseline, closeTo(62 + 16 + 48 + 24 + 96, 0.75));
  });
}
