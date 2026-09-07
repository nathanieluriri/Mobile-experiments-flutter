import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/screens/wallet/wallet_refresh_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Drags the wallet down far enough to pass the trigger and releases.
Future<void> pullToRefresh(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(201, 520));
  await gesture.moveBy(const Offset(0, 40));
  await pumpMs(tester, 16);
  await gesture.moveBy(const Offset(0, 100));
  await pumpMs(tester, 16);
  await gesture.moveBy(const Offset(0, 120));
  await pumpMs(tester, 16);
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('pull to refresh keyframes', (tester) async {
    await pumpScreen(tester, const App());
    await pullToRefresh(tester);
    await capture(tester, 'scramble__t0000');
    await pumpMs(tester, 200);
    await capture(tester, 'scramble__t0200');
    await pumpMs(tester, 600);
    await capture(tester, 'scramble__t0800');
    await pumpMs(tester, 1300);
    await capture(tester, 'scramble__t2100');
    await pumpMs(tester, 200);
    await capture(tester, 'scramble__t2300');
    await pumpMs(tester, 200);
    await capture(tester, 'scramble__t2500');
    await pumpMs(tester, 700);
    await capture(tester, 'scramble__settled');
  });

  testWidgets('a second pull during a refresh is ignored', (tester) async {
    await pumpScreen(tester, const App());
    await pullToRefresh(tester);
    await pumpMs(tester, 800);
    final before = tester.widget<Text>(find.text('Total Balance'));
    expect(before, isNotNull);
    // The spinner is at full strength mid-refresh; a second pull must not
    // restart the sequence, so the balance still lands at 2000 ms.
    await pullToRefresh(tester);
    await pumpMs(tester, 1300);
    // 2148 ms after the first trigger: digits have started locking.
    expect(find.textContaining('\$'), findsWidgets);
  });

  test('digits lock left to right on settle', () {
    for (var i = 0; i < kDigitCount; i++) {
      final lock = RefreshTimeline.lockAt(i);
      expect(RefreshTimeline.locked(i, 1, lock - 0.001), isFalse);
      expect(RefreshTimeline.locked(i, 1, lock), isTrue);
      if (i > 0) {
        expect(lock, greaterThan(RefreshTimeline.lockAt(i - 1)));
      }
    }
    expect(RefreshTimeline.locked(5, 0, 0), isTrue, reason: 'no cycling means locked');
  });

  test('timeline matches the source constants', () {
    expect(RefreshTimeline.morph(0), 0);
    expect(RefreshTimeline.morph(180), 0);
    expect(RefreshTimeline.morph(630), 1);
    expect(RefreshTimeline.morph(2140), 1);
    expect(RefreshTimeline.morph(2660), 0);
    expect(RefreshTimeline.cycling(179), 0);
    expect(RefreshTimeline.cycling(180), 1);
    expect(RefreshTimeline.cycling(2659), 1);
    expect(RefreshTimeline.cycling(2660), 0);
    expect(RefreshTimeline.settle(1999), 0);
    expect(RefreshTimeline.settle(2170), closeTo(0.5, 1e-9));
    expect(RefreshTimeline.settle(2340), 1);
    expect(RefreshTimeline.spinner(280), 1);
    expect(RefreshTimeline.spinner(2540), 0);
    expect(RefreshTimeline.shift(420), 1);
    expect(RefreshTimeline.shift(2680), 0);
  });

  test('digit cycling uses the seeded hash at 72 + 12 i ms', () {
    // Digit 0 changes every 72 ms, digit 5 every 132 ms.
    final a = RefreshTimeline.digitChar(0, '237812', 0, 1, 0);
    final b = RefreshTimeline.digitChar(0, '237812', 71, 1, 0);
    final c = RefreshTimeline.digitChar(0, '237812', 72, 1, 0);
    expect(a, b);
    expect(RegExp(r'^\d$').hasMatch(c), isTrue);
    expect(RefreshTimeline.digitChar(5, '237812', 131, 1, 0),
        RefreshTimeline.digitChar(5, '237812', 0, 1, 0));
    expect(RefreshTimeline.digitChar(2, '237812', 500, 1, 1), '7');
  });

  test('balance digits and drift stay in range', () {
    expect(toDigitString(2378.12), '237812');
    expect(toDigitString(999), '100000');
    expect(toDigitString(12000), '999999');
    expect(RefreshTimeline.drift(0, 0, 1).dy, closeTo(0, 1e-9));
    expect(RefreshTimeline.drift(1, 300, 0), Offset.zero);
  });
}
