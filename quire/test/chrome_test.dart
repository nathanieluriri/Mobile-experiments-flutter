import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/theme/springs.dart';
import 'package:flutter/physics.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/desk_top_bar.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_route.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
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

  group('the corner the two screens share', () {
    testWidgets('the reader glyph stands exactly where the desk glyph did', (
      tester,
    ) async {
      final store = LibraryStore();
      for (final entry in libraryEntries) {
        final bytes = await documentBytes(entry.fileName);
        store.storeFor(entry).loadFrom(bytes);
      }
      await pumpScreen(
        tester,
        App(
          routes: <String, WidgetBuilder>{
            kDeskRoute: (context) => DeskScreen(store: store),
          },
        ),
      );
      await settle(tester);
      final desk = tester.getRect(find.byType(HamburgerGlyph));

      final one = await storeFor(kFieldGuide);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ReaderHost(store: one),
        ),
      );
      await settle(tester);
      final reader = tester.getRect(find.byType(HamburgerGlyph));

      // Not near. The same. The turn from the menu into the arrow only reads
      // as one object changing if the object is in one place, and eight points
      // to the side is two objects taking turns.
      expect(reader, desk);
    });
  });

  group('the spring a document arrives on', () {
    /// The fastest it ever travels, as a share of the whole trip per second.
    double peak(SpringDescription spring) {
      final run = SpringSimulation(spring, 0, 1, 0);
      var best = 0.0;
      for (var ms = 1; ms <= 1500; ms++) {
        final speed = run.dx(ms / 1000);
        if (speed > best) best = speed;
      }
      return best;
    }

    test('carries a page at the speed the panel carries itself', () {
      // A trip is the whole distance the thing travels, so a share of a trip
      // per second becomes points per second by what that thing has to cross.
      final page = peak(AppSprings.documentArrival) * kScreenWidth;
      final panel = peak(AppSprings.drawer) * drawerWidth(kScreenWidth);
      expect(page, closeTo(panel, 1));
    });

    test('and so takes longer, because it has further to go', () {
      final page = springDuration(
        AppSprings.documentArrival,
        clampOvershoot: true,
      );
      final panel = springDuration(AppSprings.drawer, clampOvershoot: true);
      expect(page, greaterThan(panel));
      // In the same proportion as the two distances.
      expect(
        page.inMilliseconds / panel.inMilliseconds,
        closeTo(kScreenWidth / drawerWidth(kScreenWidth), 0.05),
      );
    });

    test('has the panel own shape, so it moves like the panel', () {
      final page = SpringSimulation(AppSprings.documentArrival, 0, 1, 0);
      final panel = SpringSimulation(AppSprings.drawer, 0, 1, 0);
      final pageHome =
          springDuration(AppSprings.documentArrival, clampOvershoot: true)
              .inMilliseconds /
          1000;
      final panelHome =
          springDuration(AppSprings.drawer, clampOvershoot: true)
              .inMilliseconds /
          1000;
      for (var i = 1; i < 10; i++) {
        expect(
          page.x(i / 10 * pageHome),
          closeTo(panel.x(i / 10 * panelHome), 0.01),
          reason: 'at ${i * 10} per cent of the way through',
        );
      }
    });
  });

  group('a document arriving', () {
    /// Where the paper's left edge is, which is what travels.
    double paperAt(WidgetTester tester) =>
        tester.getTopLeft(find.byType(SheetSurface).first).dx;

    /// Where the corner button is, which is what must not.
    double buttonAt(WidgetTester tester) =>
        tester.getTopLeft(find.byType(HamburgerGlyph)).dx;

    testWidgets('brings the paper in from the edge it will leave by', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);

      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      final width = tester.getSize(find.byType(MaterialApp)).width;
      expect(paperAt(tester), closeTo(width, 2));

      await tester.pump(kDocumentArrivalTime ~/ 2);
      final half = paperAt(tester);
      expect(half, lessThan(width));
      expect(half, greaterThan(0));

      await settle(tester);
      expect(paperAt(tester), closeTo(0, 0.01));
    });

    testWidgets('holds the corner button still while the paper travels', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // Where it starts is where it stays. A button that travelled in with the
      // page would be a second button arriving beside the desk's own, which is
      // what this whole arrangement exists to prevent.
      final home = buttonAt(tester);
      var moved = 0.0;
      for (var ms = 0; ms <= kDocumentArrivalTime.inMilliseconds; ms += 16) {
        final off = (buttonAt(tester) - home).abs();
        if (off > moved) moved = off;
        // And the paper really is travelling while it holds.
        expect(paperAt(tester), greaterThanOrEqualTo(-0.01), reason: 'at $ms');
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(moved, lessThan(0.01));
      await settle(tester);
      expect(buttonAt(tester), closeTo(home, 0.01));
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

      for (var ms = 0; ms <= kDocumentArrivalTime.inMilliseconds; ms += 8) {
        expect(paperAt(tester), greaterThanOrEqualTo(-0.01), reason: 'at $ms ms');
        await tester.pump(const Duration(milliseconds: 8));
      }
      await settle(tester);
    });

    testWidgets('darkens the desk as the paper covers it', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _deskThatOpens(store));
      await settle(tester);
      await tester.tap(find.byType(ColoredBox).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      double dim() {
        final found = tester.widgetList<ColoredBox>(
          find.byWidgetPredicate((widget) {
            if (widget is! ColoredBox) return false;
            final colour = widget.color;
            return colour.a > 0 &&
                colour.a < 1 &&
                colour.r == AppColors.ground.r &&
                colour.g == AppColors.ground.g &&
                colour.b == AppColors.ground.b;
          }),
        );
        return found.isEmpty ? 0 : found.first.color.a;
      }

      final opening = dim();
      await tester.pump(kDocumentArrivalTime ~/ 2);
      expect(dim(), greaterThan(opening));
      await settle(tester);
    });

  });
}
