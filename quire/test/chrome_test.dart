import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/desk_top_bar.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_route.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// A desk with one button on it that opens [store] the way the real one does.
Widget _deskThatOpens(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: Builder(
    builder: (context) => GestureDetector(
      onTap: () => Navigator.of(context).push<void>(
        ReaderRoute<void>(builder: (context) => ReaderHost(store: store)),
      ),
      child: const ColoredBox(
        color: AppColors.ground,
        child: SizedBox.expand(),
      ),
    ),
  ),
);

double _morph(WidgetTester tester) =>
    tester.widget<ReaderChrome>(find.byType(ReaderChrome)).backMorph;

void main() {
  group('the corner button', () {
    testWidgets('turns from the menu into the arrow as the document arrives', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);

      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // It starts as the three lines the desk had.
      expect(_morph(tester), lessThan(0.05));

      await tester.pump(kOpenDocument ~/ 2);
      final half = _morph(tester);
      expect(half, greaterThan(0));
      expect(half, lessThan(1));

      await settle(tester);
      expect(_morph(tester), 1);
    });

    testWidgets('the glyph is a readout of the route, not a second animation',
        (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(kOpenDocument ~/ 3);

      // Whatever the band was told is exactly what the glyph is drawing, so
      // the two can never disagree about how far the turn has got.
      final glyph = tester.widget<HamburgerGlyph>(find.byType(HamburgerGlyph));
      expect(glyph.progress, _morph(tester));
      await settle(tester);
    });

    testWidgets('turns back into the menu on the way out', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await settle(tester);
      expect(_morph(tester), 1);

      final context = tester.element(find.byType(ReaderHost));
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(kCloseDocument ~/ 2);
      final half = _morph(tester);
      expect(half, greaterThan(0));
      expect(half, lessThan(1));
      await settle(tester);
    });

    testWidgets('is an arrow outright where nothing pushed the reader', (
      tester,
    ) async {
      // A test, or a deep link: there is no journey for the glyph to be part
      // way through, so it is simply the way back.
      final store = await storeFor(kFieldGuide);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReaderHost(store: store),
        ),
      );
      await settle(tester);
      expect(_morph(tester), 1);
    });
  });

  group('a button in the band', () {
    testWidgets('wears no plate of its own, so the band reads as one thing', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReaderHost(store: store),
        ),
      );
      await settle(tester);

      // Every container inside the band is the size of a header button, and
      // none of them is filled: the glyphs sit on the band's own ground.
      final plates = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(ReaderChrome),
          matching: find.byType(Container),
        ),
      );
      expect(plates, isNotEmpty);
      for (final plate in plates) {
        final decoration = plate.decoration;
        if (decoration is! BoxDecoration) continue;
        expect(decoration.color, isNull, reason: 'a button wears a plate');
        expect(decoration.border, isNull, reason: 'a button wears a rule');
      }
    });

    testWidgets('a button that finishes something keeps its accent', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReaderHost(store: store),
        ),
      );
      await settle(tester);
      store.lock = ReaderLock.back;
      await tester.pump();
      await settle(tester);

      final filled = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ReaderChrome),
              matching: find.byType(Container),
            ),
          )
          .where((c) {
            final decoration = c.decoration;
            return decoration is BoxDecoration &&
                decoration.color == AppColors.accent;
          });
      expect(filled, hasLength(1));
    });
  });

  group('a document arriving', () {
    testWidgets('comes in from the edge it will leave by', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);

      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // It starts off the right hand edge, whole.
      final width = tester.getSize(find.byType(MaterialApp)).width;
      var at = tester.getTopLeft(find.byType(ReaderHost)).dx;
      expect(at, closeTo(width, 2));

      await tester.pump(kDocumentArrivalTime ~/ 2);
      final half = tester.getTopLeft(find.byType(ReaderHost)).dx;
      expect(half, lessThan(at));
      expect(half, greaterThan(0));

      await settle(tester);
      at = tester.getTopLeft(find.byType(ReaderHost)).dx;
      expect(at, closeTo(0, 0.01));
    });

    testWidgets('never springs past the edge and shows the desk beside it', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // A drawer that overshoots shows more drawer. A page that overshoots
      // shows the desk down its far edge, so this one is clamped.
      for (var ms = 0; ms <= kDocumentArrivalTime.inMilliseconds; ms += 8) {
        expect(
          tester.getTopLeft(find.byType(ReaderHost)).dx,
          greaterThanOrEqualTo(-0.01),
          reason: 'at $ms ms',
        );
        await tester.pump(const Duration(milliseconds: 8));
      }
      await settle(tester);
    });

    testWidgets('darkens the desk where it stands rather than dragging the '
        'dark across with it', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(kDocumentArrivalTime ~/ 2);

      // The dim is part way in, over the whole screen, and standing still
      // while the page is still travelling. A dim that moved with the page
      // would leave the desk it has not reached yet undarkened.
      final dim = find.byWidgetPredicate((widget) {
        if (widget is! ColoredBox) return false;
        final colour = widget.color;
        return colour.a > 0 &&
            colour.a < 1 &&
            colour.r == AppColors.ground.r &&
            colour.g == AppColors.ground.g &&
            colour.b == AppColors.ground.b;
      });
      expect(dim, findsWidgets);
      expect(tester.getTopLeft(dim.first), Offset.zero);
      expect(
        tester.getTopLeft(find.byType(ReaderHost)).dx,
        greaterThan(0),
      );
      await settle(tester);
    });
  });
}
