import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/painting/spinner_painter.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/widgets/pull_to_refresh.dart';

import 'support/golden.dart';

/// The loop, if it is on screen at all.
SpinnerPainter? loop(WidgetTester tester) {
  final found = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  for (final paint in found) {
    final painter = paint.painter;
    if (painter is SpinnerPainter) return painter;
  }
  return null;
}

Widget _list({
  required Future<void> Function() onRefresh,
  bool enabled = true,
}) => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => ColoredBox(
      color: AppColors.ground,
      child: PullToRefresh(
        enabled: enabled,
        onRefresh: onRefresh,
        child: ListView.builder(
          physics: const ClampingScrollPhysics(),
          itemCount: 30,
          itemExtent: 60,
          itemBuilder: (context, i) => SizedBox(height: 60, child: Text('$i')),
        ),
      ),
    ),
  },
);

void main() {
  group('a list pulled at the top', () {
    testWidgets('shows nothing until it is pulled', (tester) async {
      await pumpScreen(tester, _list(onRefresh: () async {}));
      await settle(tester);
      expect(loop(tester), isNull);
    });

    testWidgets('the loop is a readout of the pull, not a clock', (
      tester,
    ) async {
      await pumpScreen(tester, _list(onRefresh: () async {}));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      final little = loop(tester);
      expect(little, isNotNull);
      // Short of the mark it is faint, and it has turned a little.
      expect(little!.color, AppColors.inkFaint);
      final turnedALittle = little.turns;
      expect(turnedALittle, greaterThan(0));

      await drag.moveBy(const Offset(0, 40));
      await tester.pump();
      final more = loop(tester)!;
      expect(more.turns, greaterThan(turnedALittle));
      await drag.up();
      await settle(tester);
    });

    testWidgets('past the mark it lights, and letting go does the work', (
      tester,
    ) async {
      var ran = 0;
      await pumpScreen(tester, _list(onRefresh: () async => ran++));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, kPullThreshold + 20));
      await tester.pump();
      expect(loop(tester)!.color, AppColors.accentBright);
      expect(ran, 0);

      await drag.up();
      await tester.pump();
      expect(ran, 1);
      await settle(tester);
    });

    testWidgets('short of the mark, letting go does nothing', (tester) async {
      var ran = 0;
      await pumpScreen(tester, _list(onRefresh: () async => ran++));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, kPullThreshold - 20));
      await tester.pump();
      await drag.up();
      await settle(tester);

      expect(ran, 0);
      expect(loop(tester), isNull);
    });

    testWidgets('the loop turns on its own only while there is work', (
      tester,
    ) async {
      final gate = Completer<void>();
      await pumpScreen(tester, _list(onRefresh: () => gate.future));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, kPullThreshold + 20));
      await drag.up();
      await tester.pump();

      // Working: it turns without a finger on it.
      final was = loop(tester)!.turns;
      await tester.pump(const Duration(milliseconds: 300));
      expect(loop(tester)!.turns, isNot(was));

      gate.complete();
      await tester.pump();
      await settle(tester);
      // And then it goes.
      expect(loop(tester), isNull);
    });

    testWidgets('a pull is not read while the work is still running', (
      tester,
    ) async {
      var ran = 0;
      final gate = Completer<void>();
      await pumpScreen(
        tester,
        _list(
          onRefresh: () {
            ran++;
            return gate.future;
          },
        ),
      );
      await settle(tester);

      final first = await tester.startGesture(const Offset(200, 300));
      await first.moveBy(const Offset(0, kPullThreshold + 20));
      await first.up();
      await tester.pump();
      expect(ran, 1);

      final second = await tester.startGesture(const Offset(200, 300));
      await second.moveBy(const Offset(0, kPullThreshold + 20));
      await second.up();
      await tester.pump();
      expect(ran, 1);

      gate.complete();
      await settle(tester);
    });

    testWidgets('a list that cannot be refreshed never shows the loop', (
      tester,
    ) async {
      var ran = 0;
      await pumpScreen(
        tester,
        _list(enabled: false, onRefresh: () async => ran++),
      );
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, kPullThreshold + 40));
      await tester.pump();
      expect(loop(tester), isNull);
      await drag.up();
      await settle(tester);
      expect(ran, 0);
    });

    testWidgets('scrolling down, and overscrolling the bottom, mean nothing', (
      tester,
    ) async {
      var ran = 0;
      await pumpScreen(tester, _list(onRefresh: () async => ran++));
      await settle(tester);

      await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
      await settle(tester);
      expect(loop(tester), isNull);

      // At the bottom now, and pulling further up is the other end.
      await tester.fling(find.byType(ListView), const Offset(0, -600), 2000);
      await settle(tester);
      expect(ran, 0);
      expect(loop(tester), isNull);
    });
  });
}
