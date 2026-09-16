import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/config/flags.dart';
import 'package:quire/painting/spinner_painter.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';
import 'package:quire/widgets/pull_to_refresh.dart';

import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/screens/desk/list_body.dart';
import 'package:quire/widgets/skeleton.dart';
import 'desk_test.dart' show deskStore;
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

/// Real frames rather than one long one, so tickers and controllers actually
/// run: a single pump of 700 ms advances the clock once and animates nothing.
Future<void> _frames(WidgetTester tester, int ms) async {
  for (var spent = 0; spent < ms; spent += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Widget _list({
  required Future<void> Function() onRefresh,
  bool enabled = true,
  PullStyle style = PullStyle.follow,
  int items = 30,
  ScrollPhysics physics = const ClampingScrollPhysics(),
}) => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => ColoredBox(
      color: AppColors.ground,
      child: PullToRefresh(
        enabled: enabled,
        style: style,
        onRefresh: onRefresh,
        child: ListView.builder(
          physics: physics,
          itemCount: items,
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
        // The goo is thick, so it is given a moment to catch the finger up.
        await pumpMs(tester, 400);
        // Within a point: the scroll view itself takes up the slop before it
        // reports the overscroll this widget reads.
        expect(await topOfFirstItem(tester), closeTo(rest, 1));
        expect(loop(tester), isNotNull);
        if (style == PullStyle.goo) {
          // The goo is the app's own material, so it is worth pictures: on
          // the way out of the edge, at work, and on the way back into it.
          await capture(tester, 'pull__goo_coming');
        }
        await drag.up();
        await settle(tester);
      });
    }
  });

  group('a pull the list itself cannot carry', () {
    testWidgets('works on a list shorter than the screen', (tester) async {
      var ran = 0;
      await pumpScreen(
        tester,
        _list(
          items: 3,
          onRefresh: () async => ran++,
          // What the desk's own bodies use, so a short desk can be pulled.
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
        ),
      );
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(loop(tester), isNotNull, reason: 'a short list still pulls');
      await drag.up();
      await settle(tester);
      expect(ran, 1);
    });

    testWidgets('works where the list runs past its own top', (tester) async {
      var ran = 0;
      await pumpScreen(
        tester,
        _list(
          onRefresh: () async => ran++,
          // Bouncing physics never overscroll: the pull is in the offset.
          physics: const BouncingScrollPhysics(),
        ),
      );
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 144));
      await tester.pump();
      expect(loop(tester), isNotNull, reason: 'the offset is the pull');
      await drag.up();
      await settle(tester);
      expect(ran, 1);
    });
  });

  group('the list put away while the loop is still up', () {
    testWidgets('takes nothing down with it', (tester) async {
      final held = Completer<void>();
      await pumpScreen(tester, _list(onRefresh: () => held.future));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 100));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(loop(tester), isNotNull);

      // The work finishes and, before the loop has been taken back up, the
      // body it lives in is replaced, which is what a refresh that empties
      // the desk does.
      held.complete();
      await tester.pump();
      await pumpScreen(tester, const SizedBox.shrink());
      await pumpMs(tester, 600);
      expect(tester.takeException(), isNull);
      await settle(tester);
    });
  });

  group('where the loop sits', () {
    testWidgets('stays clear of the first row while the list follows', (
      tester,
    ) async {
      await pumpScreen(tester, _list(onRefresh: () async {}));
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      for (final pull in <double>[20, 40, 40]) {
        await drag.moveBy(Offset(0, pull));
        await tester.pump();
        final ring = tester.getRect(
          find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter is SpinnerPainter,
          ),
        );
        expect(
          ring.bottom,
          lessThanOrEqualTo(tester.getRect(find.text('0')).top + 1),
          reason: 'the loop is in the space, not over the list',
        );
      }
      await drag.up();
      await settle(tester);
    });
  });

  group('the goo through the whole pull', () {
    testWidgets('comes out of the edge, works loose, and melts back', (
      tester,
    ) async {
      final held = Completer<void>();
      await pumpScreen(
        tester,
        _list(onRefresh: () => held.future, style: PullStyle.goo),
      );
      await settle(tester);

      final drag = await tester.startGesture(const Offset(200, 300));
      await drag.moveBy(const Offset(0, 100));
      await tester.pump();
      await drag.up();
      await tester.pump();
      await pumpMs(tester, 500);
      await capture(tester, 'pull__goo_working');

      // While it works, what it is over has gone quiet, so the goo reads as
      // being in front of the list rather than drawn into it.
      final hush = tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where(
        (box) => box.color.a > 0 && box.color.a < 1,
      );
      expect(hush, isNotEmpty, reason: 'the list is hushed under the goo');

      held.complete();
      await tester.pump();
      await pumpMs(tester, kPullHold.inMilliseconds + 140);
      await capture(tester, 'pull__goo_going');
      // Still on its way home rather than gone in a frame: this stuff does
      // not snap anywhere.
      expect(loop(tester), isNotNull);

      await settle(tester);
      expect(loop(tester), isNull);
      // And nothing is left over the list once it has gone.
      expect(
        tester.widgetList<ColoredBox>(find.byType(ColoredBox)).where(
          (box) => box.color.a > 0 && box.color.a < 1,
        ),
        isEmpty,
      );
    });
  });

  group('what is under the goo while it works', () {
    testWidgets('waits in its own outline, and comes back to itself', (
      tester,
    ) async {
      final library = await deskStore();
      final held = Completer<void>();
      await pumpScreen(
        tester,
        App(
          routes: <String, WidgetBuilder>{
            kDeskRoute: (context) => ColoredBox(
              color: AppColors.ground,
              child: PullToRefresh(
                style: PullStyle.goo,
                onRefresh: () => held.future,
                child: DeskListBody(
                  library: library,
                  entries: library.visible,
                ),
              ),
            ),
          },
        ),
      );
      await settle(tester);
      expect(find.byType(SkeletonRow), findsNothing);

      final drag = await tester.startGesture(const Offset(200, 420));
      for (var i = 0; i < 6; i++) {
        await drag.moveBy(const Offset(0, 24));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await _frames(tester, 700);

      // Every row is waiting in its outline, and the rows themselves are on
      // their way out rather than thrown away.
      expect(find.byType(SkeletonRow), findsNWidgets(library.visible.length));
      final quiet = tester
          .widgetList<Skeletal>(find.byType(Skeletal))
          .first
          .quiet;
      expect(quiet, greaterThan(0.5));
      await capture(tester, 'desk__skeletons');

      held.complete();
      await settle(tester);
      // And the desk is itself again, with nothing of the wait left on it.
      expect(
        tester.widgetList<Skeletal>(find.byType(Skeletal)).every(
          (row) => row.quiet == 0,
        ),
        isTrue,
      );
      expect(find.byType(SkeletonRow), findsNothing);
      expect(find.byType(DocumentRow), findsNWidgets(library.visible.length));
    });
  });
}
