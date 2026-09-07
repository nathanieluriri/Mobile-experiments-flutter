import 'package:coverdeck/theme/colors.dart';
import 'package:coverdeck/widgets/bottom_dock.dart';
import 'package:coverdeck/widgets/tab_bar_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// The dock alone on the app's background, big enough to read its geometry.
Widget _strip(int selected, TabBarController controller) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: kFontFamily),
    home: ColoredBox(
      color: AppColors.background,
      child: Center(
        child: BottomDock(selected: selected, onSelect: (_) {}, controller: controller),
      ),
    ),
  );
}

void main() {
  for (final (index, name) in const [(0, 'deck'), (1, 'browse'), (2, 'library')]) {
    testWidgets('dock on the $name tab', (tester) async {
      final controller = TabBarController();
      addTearDown(controller.dispose);
      await pumpScreen(tester, _strip(index, controller), phone: kStrip);
      await capture(tester, 'dock__$name');
    });
  }

  testWidgets('dock compact', (tester) async {
    final controller = TabBarController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, _strip(0, controller), phone: kStrip);
    controller.handleScroll(200, 1000);
    await tester.pump();
    await pumpMs(tester, 1200);
    expect(find.text('Deck'), findsNothing, reason: 'labels go when the dock shrinks');
    await capture(tester, 'dock__compact');
  });

  testWidgets('the pill springs across the whole shape change', (tester) async {
    final controller = TabBarController();
    addTearDown(controller.dispose);
    await pumpScreen(tester, _strip(0, controller), phone: kStrip);
    final expanded = tester.getSize(find.byType(BottomDock));

    controller.handleScroll(200, 1000);
    await tester.pump();
    expect(find.text('Deck'), findsNothing, reason: 'the contents change at once');
    expect(
      tester.getSize(find.byType(BottomDock)),
      expanded,
      reason: 'while the pill itself has not started to move',
    );

    await pumpMs(tester, 60);
    final midway = tester.getSize(find.byType(BottomDock));
    expect(midway.width, lessThan(expanded.width));
    expect(midway.height, lessThan(expanded.height));

    await pumpMs(tester, 1200);
    final compact = tester.getSize(find.byType(BottomDock));
    expect(compact.width, lessThan(midway.width), reason: 'and keeps shrinking');
    expect(compact.height, lessThan(midway.height));
  });

  group('the compact latch', () {
    test('stays open near the top of a list', () {
      final controller = TabBarController();
      addTearDown(controller.dispose);
      controller.handleScroll(0, 1000);
      expect(controller.compact, isFalse);
      controller.handleScroll(28, 1000);
      expect(controller.compact, isFalse, reason: 'the arming distance is 28');
    });

    test('closes on the way down and opens on the way back up', () {
      final controller = TabBarController();
      addTearDown(controller.dispose);
      controller.handleScroll(28, 1000);
      controller.handleScroll(34, 1000);
      expect(controller.compact, isFalse, reason: 'six past the anchor is under the threshold');
      controller.handleScroll(40, 1000);
      expect(controller.compact, isTrue, reason: 'twelve past the anchor closes it');
      controller.handleScroll(35, 1000);
      expect(controller.compact, isTrue, reason: 'five back is under the threshold');
      controller.handleScroll(31, 1000);
      expect(controller.compact, isFalse, reason: 'nine back opens it again');
    });

    test('scrolling back to the top always opens it', () {
      final controller = TabBarController();
      addTearDown(controller.dispose);
      controller.handleScroll(28, 1000);
      controller.handleScroll(400, 1000);
      expect(controller.compact, isTrue);
      controller.handleScroll(10, 1000);
      expect(controller.compact, isFalse);
    });

    test('a tab press always opens it', () {
      final controller = TabBarController();
      addTearDown(controller.dispose);
      controller.handleScroll(400, 1000);
      expect(controller.compact, isTrue);
      controller.expand();
      expect(controller.compact, isFalse);
    });
  });
}
