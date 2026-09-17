import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart' show fittedScale, insetsInFrame;
import 'package:quire/painting/grid_painter.dart';
import 'package:quire/screens/desk/desk_top_bar.dart' show kMenuButtonTop;
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _reader(DocumentStore store, {VoidCallback? onLeave}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderScreen(
    store: store,
    bodyBuilder: (context) => SheetBody(store: store),
    onLeave: onLeave,
  ),
);

/// One pane of the grid as it was last painted.
Finder _pane(WidgetTester tester, GridPane pane) {
  final painter = _painter(tester, pane);
  return find.byWidgetPredicate(
    (widget) => widget is CustomPaint && identical(widget.painter, painter),
  );
}

GridPainter _painter(WidgetTester tester, GridPane pane) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GridPainter>()
    .where((painter) => painter.pane == pane)
    .last;

/// The top of the grid's letters on the glass.
double _lettersTop(WidgetTester tester) =>
    tester.getTopLeft(_pane(tester, GridPane.letters)).dy;

/// The band's lower edge on the glass, which is the foot of its ground.
double _bandEdge(WidgetTester tester) => tester
    .getBottomLeft(
      find
          .descendant(
            of: find.byType(ReaderChrome),
            matching: find.byType(DecoratedBox),
          )
          .first,
    )
    .dy;

double _hidden(WidgetTester tester) =>
    tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden;

/// Where the top left of the sheet's cells is on the glass: where the pane of
/// cells is on screen, less how far the sheet has been pushed inside it.
Offset _cellsOnGlass(WidgetTester tester) =>
    tester.getTopLeft(_pane(tester, GridPane.cells)) -
    _painter(tester, GridPane.cells).offset;

Future<void> _push(WidgetTester tester, double down) async {
  await tester.drag(
    find.byType(SheetGrid),
    Offset(0, -down),
    warnIfMissed: false,
  );
  await settle(tester);
}

void main() {
  group('the letters under the band', () {
    testWidgets(
      'sit directly under the band, and under the status bar once it goes',
      (tester) async {
        final store = await storeFor(kPressRunCosts);
        await pumpScreen(tester, _reader(store));
        await settle(tester);
        expect(_hidden(tester), 0);
        expect(_lettersTop(tester), kPhone.top + kHeadBandHeight);
        expect(_lettersTop(tester), closeTo(_bandEdge(tester), 0.01));

        // Reading on takes the band away, and nothing is left where it was.
        await _push(tester, 300);
        expect(_hidden(tester), 1);
        expect(_lettersTop(tester), kPhone.top);

        // Going back brings it, and the letters are pushed down under it.
        await _push(tester, -120);
        expect(_hidden(tester), 0);
        expect(_lettersTop(tester), kPhone.top + kHeadBandHeight);
      },
    );

    testWidgets('meet a shorter status bar where that phone puts it', (
      tester,
    ) async {
      const phone = Phone('Android', Size(402, 874), top: 24, bottom: 16);
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store), phone: phone);
      await settle(tester);
      expect(_lettersTop(tester), phone.top + kHeadBandHeight);
      expect(_lettersTop(tester), closeTo(_bandEdge(tester), 0.01));
      await _push(tester, 300);
      expect(_lettersTop(tester), phone.top);
    });

    testWidgets(
      'go up and come down with the band on every frame, never a step',
      (tester) async {
        final store = await storeFor(kPressRunCosts);
        await pumpScreen(tester, _reader(store));
        await settle(tester);

        Future<List<double>> follow({required bool going}) async {
          final seen = <double>[_lettersTop(tester)];
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            final top = _lettersTop(tester);
            // Nothing between the band and the letters at any moment.
            expect(top, closeTo(_bandEdge(tester), 0.01), reason: '$frame');
            final step = top - seen.last;
            // One way only, and a little at a time.
            expect(going ? -step : step, greaterThan(-0.01), reason: '$frame');
            expect(step.abs(), lessThan(kHeadBandHeight / 8), reason: '$frame');
            seen.add(top);
          }
          return seen;
        }

        await tester.drag(
          find.byType(SheetGrid),
          const Offset(0, -300),
          warnIfMissed: false,
        );
        final up = await follow(going: true);
        expect(up.last, kPhone.top);
        expect(
          up.where((top) => top > kPhone.top + 4 && top < up.first - 4),
          isNotEmpty,
          reason: 'the letters are seen on their way, not cut',
        );

        await tester.drag(
          find.byType(SheetGrid),
          const Offset(0, 120),
          warnIfMissed: false,
        );
        final down = await follow(going: false);
        expect(down.last, kPhone.top + kHeadBandHeight);
      },
    );

    testWidgets('leave the rows being read where they are', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      // Well into the sheet, with the band back in.
      await _push(tester, 600);
      await _push(tester, -150);
      expect(_hidden(tester), 0);
      final held = _cellsOnGlass(tester);

      // A lock takes the band away without anything else moving the sheet.
      store.lock = ReaderLock.page;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _cellsOnGlass(tester).dy,
          closeTo(held.dy, 0.01),
          reason: '$frame',
        );
      }
      await settle(tester);
      expect(_hidden(tester), 1);
      expect(_lettersTop(tester), kPhone.top);

      store.lock = ReaderLock.none;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _cellsOnGlass(tester).dy,
          closeTo(held.dy, 0.01),
          reason: '$frame',
        );
      }
      await settle(tester);
      expect(_hidden(tester), 0);
      expect(_lettersTop(tester), kPhone.top + kHeadBandHeight);
    });

    testWidgets('carry a sheet at its top with them', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      // At the top there is no row above the first for the letters to lie
      // over, so the first row goes with them.
      final gap = _cellsOnGlass(tester).dy - _lettersTop(tester);
      store.lock = ReaderLock.page;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          _cellsOnGlass(tester).dy - _lettersTop(tester),
          closeTo(gap, 0.01),
          reason: '$frame',
        );
      }
      await settle(tester);
      expect(_lettersTop(tester), kPhone.top);
      store.lock = ReaderLock.none;
      await settle(tester);
      expect(
        _cellsOnGlass(tester).dy - _lettersTop(tester),
        closeTo(gap, 0.01),
      );
    });

    testWidgets('stay under the head find lays over the band', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReaderHost(store: store),
        ),
      );
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);

      // The band leaves under find's head, and the letters stay under it.
      await _push(tester, 300);
      expect(_hidden(tester), 1);
      expect(_lettersTop(tester), kPhone.top + kHeadBandHeight);

      // With find put away there is nothing over them.
      await tester.tap(find.bySemanticsLabel(RegExp('Close find')));
      await settle(tester);
      expect(_lettersTop(tester), kPhone.top);
    });
  });

  group('the band over a sheet', () {
    testWidgets('a pull at the top brings it back and letting go keeps it', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await _push(tester, 300);
      expect(_hidden(tester), 1);
      // All the way back and on past the top, and let go: the sheet going
      // back to its top is not the reader reading on.
      await _push(tester, -900);
      expect(_hidden(tester), 0);
    });

    testWidgets('a push past the foot takes it and letting go keeps it gone', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await _push(tester, 6000);
      expect(_hidden(tester), 1);
    });

    testWidgets('once gone, its way back takes no touch', (tester) async {
      var left = false;
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store, onLeave: () => left = true));
      await settle(tester);
      await _push(tester, 300);
      expect(_hidden(tester), 1);

      // Where the way back sits once the band has gone, faded out behind the
      // status bar rather than off the glass.
      await tester.tapAt(
        const Offset(
          kTopBarPaddingX + kBurgerTarget / 2,
          kSafeTop + kMenuButtonTop + kBurgerTarget / 2 + kHeadBandHidden,
        ),
      );
      await settle(tester);
      expect(left, isFalse);
    });

    testWidgets('sheet_band keyframes', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.drag(
        find.byType(SheetGrid),
        const Offset(0, -200),
        warnIfMissed: false,
      );
      await tester.pump();
      await capture(tester, 'sheet_band__t0000');
      await pumpMs(tester, 120);
      await capture(tester, 'sheet_band__t0120');
      await pumpMs(tester, 480);
      await capture(tester, 'sheet_band__t0600');
      await settle(tester);
    });
  });

  group('the phone insets the design frame meets', () {
    test(
      'a phone taller than the design meets its bars where the frame is',
      () {
        const screen = Size(393, 895);
        final scale = fittedScale(screen);
        final down = (screen.height - kScreenHeight * scale) / 2;
        final inFrame = insetsInFrame(
          screen,
          const EdgeInsets.only(top: 37, bottom: 16),
        );
        // The frame starts part of the way down the status bar, so only the
        // rest of the bar is over it.
        expect(inFrame.top, closeTo((37 - down) / scale, 1e-9));
        // And the gesture bar is wholly in the margin under the frame.
        expect(inFrame.bottom, 0);
        expect(inFrame.left, 0);
        expect(inFrame.right, 0);
      },
    );

    test("a phone of the design's own shape keeps every inset", () {
      const screen = Size(kScreenWidth * 2, kScreenHeight * 2);
      final inFrame = insetsInFrame(
        screen,
        const EdgeInsets.only(top: 124, bottom: 68),
      );
      expect(inFrame.top, 62);
      expect(inFrame.bottom, 34);
    });

    test(
      'a phone wider than the design meets its sides where the frame is',
      () {
        const screen = Size(600, kScreenHeight);
        final inFrame = insetsInFrame(
          screen,
          const EdgeInsets.fromLTRB(40, 30, 120, 20),
        );
        expect(inFrame.top, 30);
        expect(inFrame.bottom, 20);
        expect(inFrame.left, 0);
        expect(inFrame.right, 120 - (600 - kScreenWidth) / 2);
      },
    );
  });
}
