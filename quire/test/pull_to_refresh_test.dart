import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/config/flags.dart';
import 'package:quire/painting/spinner_painter.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';
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
  PullStyle style = PullStyle.follow,
}) => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => ColoredBox(
      color: AppColors.ground,
      child: PullToRefresh(
        enabled: enabled,
        style: style,
        onRefresh: onRefresh,
        child: ListView.builder(
          physics: const ClampingScrollPhysics(),
          itemCount: 30,
          itemExtent: 60,
          itemBuilder: (context, i) => SizedBox(
            height: 60,
            child: DefaultTextStyle(
              style: AppText.rowTitle.copyWith(color: AppColors.ink),
              child: Text('$i'),
            ),
          ),
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

  group('the shape the loop takes', () {
    testWidgets('is a circle drawn on by the pull', (tester) async {
      await pumpScreen(tester, _list(onRefresh: () async {}));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      final part = loop(tester)!;
      // Not the whole ring yet, and not a crinkle anywhere on it.
      expect(part.arc, greaterThan(0));
      expect(part.arc, lessThan(1));
      expect(part.trace, 0);

      await drag.moveBy(const Offset(0, 60));
      await tester.pump();
      expect(loop(tester)!.arc, 1);
      expect(loop(tester)!.trace, 0);
      await drag.up();
      await settle(tester);
    });

    testWidgets('turns into the zig zag while it works, once', (tester) async {
      final held = Completer<void>();
      await pumpScreen(tester, _list(onRefresh: () => held.future));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 100));
      await tester.pump();
      await drag.up();
      await tester.pump();

      // The work has started on a plain circle.
      expect(loop(tester)!.trace, 0);
      await capture(tester, 'pull__trace_t0000');

      // And the crinkle travels round it.
      await pumpMs(tester, kSpinnerTrace.inMilliseconds ~/ 2);
      final halfway = loop(tester)!.trace;
      expect(halfway, greaterThan(0));
      expect(halfway, lessThan(1));
      await capture(tester, 'pull__trace_t0350');

      await pumpMs(tester, kSpinnerTrace.inMilliseconds ~/ 2);
      expect(loop(tester)!.trace, 1);
      await capture(tester, 'pull__trace_t0700');

      // It stays that shape for the rest of the work rather than crinkling
      // again on every turn.
      await pumpMs(tester, 600);
      expect(loop(tester)!.trace, 1);

      held.complete();
      await settle(tester);
    });
  });

  group('the three answers to a pull', () {
    Future<double> topOfFirstItem(WidgetTester tester) async =>
        tester.getRect(find.text('0')).top;

    testWidgets('following the finger opens a space at the head', (
      tester,
    ) async {
      await pumpScreen(tester, _list(onRefresh: () async {}));
      await settle(tester);
      final rest = await topOfFirstItem(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 60));
      await tester.pump();
      final pulled = await topOfFirstItem(tester);
      expect(
        pulled,
        greaterThan(rest + 20),
        reason: 'the list comes down with the finger',
      );
      // The loop is in that space rather than over the list.
      expect(tester.getRect(find.byType(CustomPaint).first).top, lessThan(pulled));
      await drag.up();
      await settle(tester);
    });

    for (final style in <PullStyle>[PullStyle.overlay, PullStyle.goo]) {
      testWidgets('$style holds the list still and comes over it', (
        tester,
      ) async {
        await pumpScreen(
          tester,
          _list(onRefresh: () async {}, style: style),
        );
        await settle(tester);
        final rest = await topOfFirstItem(tester);

        final drag = await tester.startGesture(const Offset(200, 300));
        await drag.moveBy(const Offset(0, 60));
        await tester.pump();
        // Within a point: the scroll view itself takes up the slop before it
        // reports the overscroll this widget reads.
        expect(await topOfFirstItem(tester), closeTo(rest, 1));
        expect(loop(tester), isNotNull);
        await drag.up();
        await settle(tester);
      });
    }
  });
}
