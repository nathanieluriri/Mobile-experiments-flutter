import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _host(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

/// How wide the pages are actually being drawn.
double _drawnWidth(WidgetTester tester) =>
    tester.widget<PdfPageView>(find.byType(PdfPageView).first).width;

void main() {
  group('the size the reader holds the page at', () {
    test('a document opens fitting the width', () async {
      final store = await storeFor(kFieldGuide);
      expect(store.fit, FitMode.width);
      expect(store.zoom, 1);
    });

    test('a pinch takes the size off the fit and gives it to the reader',
        () async {
      final store = await storeFor(kFieldGuide);
      store.zoomTo(2.5);
      expect(store.fit, FitMode.free);
      expect(store.zoom, 2.5);
    });

    test('it cannot be pinched past what a phone can hold', () async {
      final store = await storeFor(kFieldGuide);
      store.zoomTo(40);
      expect(store.zoom, kZoomMax);
      store.zoomTo(0.01);
      expect(store.zoom, kZoomMin);
    });

    test('a named fit takes the size back off the reader', () async {
      final store = await storeFor(kFieldGuide);
      store.zoomTo(3);
      store.fit = FitMode.page;
      expect(store.fit, FitMode.page);
      expect(store.fit.byHand, isFalse);
    });

    test('the type scales only between the two stops', () async {
      final store = await storeFor(kHouseStyle);
      store.textScale = 9;
      expect(store.textScale, kTextScaleMax);
      store.textScale = 0;
      expect(store.textScale, kTextScaleMin);
    });
  });

  group('a page drawn at the size it is held at', () {
    testWidgets('fits the width it is given, to the point', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      expect(_drawnWidth(tester), kSheetWidth);
    });

    testWidgets('is set again wider rather than magnified', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      store.zoomTo(2);
      await tester.pump();
      await tester.pump();

      // The page is drawn at twice the width, which means its display list is
      // painted at twice the size: the type is re-set, not blown up.
      expect(_drawnWidth(tester), closeTo(kSheetWidth * 2, 0.01));
    });

    testWidgets('grows sideways only once there is somewhere to go', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      // At rest the strip has one scroll view, and it runs down the page.
      var scrollables = find.byType(Scrollable).evaluate().toList();
      expect(scrollables, hasLength(1));

      store.zoomTo(2);
      await tester.pump();
      await tester.pump();

      // Zoomed, a second one appears to carry the page sideways.
      scrollables = find.byType(Scrollable).evaluate().toList();
      expect(scrollables, hasLength(2));
    });

    testWidgets('fitting the whole page never pushes it off the sides', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      store.zoomTo(3);
      await tester.pump();
      await tester.pump();
      expect(find.byType(Scrollable).evaluate(), hasLength(2));

      store.fit = FitMode.page;
      await tester.pump();
      await tester.pump();

      // The whole page means the whole page: never wider than the window it
      // is being read through, so there is nothing to pan to.
      expect(_drawnWidth(tester), lessThanOrEqualTo(kSheetWidth));
      expect(find.byType(Scrollable).evaluate(), hasLength(1));
    });

    testWidgets('the reader keeps the page they were on across a fit', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      store.position = 3;
      await tester.pump();
      await tester.pump();
      expect(store.position, 3);

      store.fit = FitMode.page;
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(store.position, 3);
    });
  });

  group('the type of a document with no pages', () {
    testWidgets('is set larger when the reader asks for larger', (
      tester,
    ) async {
      final store = await storeFor(kHouseStyle);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      final was = tester
          .renderObject<RenderBox>(find.byType(Text).first)
          .size
          .height;

      store.textScale = 1.6;
      await tester.pump();
      await settle(tester);

      final now = tester
          .renderObject<RenderBox>(find.byType(Text).first)
          .size
          .height;
      expect(now, greaterThan(was));
    });
  });
}
