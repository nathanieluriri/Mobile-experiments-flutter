import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/screens/reader/bodies/page_states.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/render_plan.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the page block', () {
    test('a page keeps the shape its own file gives it', () async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      expect(pages.pageCount, 6);
      expect(pages.sizeOf(0), const Size(612, 792));
      final layout = PdfLayout.of(pages, kSheetWidth);
      expect(layout.heightOf(0), closeTo(372 * 792 / 612, 0.01));
    });

    test('pages stack edge to edge, parted by one hairline', () async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      final layout = PdfLayout.of(pages, kSheetWidth);
      expect(layout.topOf(0), 0);
      expect(layout.topOf(1), closeTo(layout.heightOf(0) + kPageRule, 0.01));
      expect(
        layout.extent,
        closeTo(6 * layout.heightOf(0) + 5 * kPageRule, 0.01),
      );
    });

    test('the page you are on is the one filling most of the viewport', () {
      const layout = PdfLayout(<double>[400, 400, 400]);
      expect(layout.pageAt(0, kSheetHeight), 0);
      expect(layout.pageAt(300, kSheetHeight), 1);
      expect(layout.pageAt(layout.extent - kSheetHeight, kSheetHeight), 2);
    });

    test('a page is interpreted when it is wanted, and not before', () async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      expect(pages.holds(0), isFalse);
      expect(pages.pageAt(0).ready, isFalse);
      expect(pages.runNext(0, 1), 0);
      expect(pages.holds(0), isTrue);
      expect(pages.runNext(0, 1), 1);
      expect(pages.runNext(0, 1), isNull);
      final page = pages.pageAt(0);
      expect(page.ready, isTrue);
      expect(page.plan, RenderPlan.rich);
      expect(page.runs.first.text, 'A Field Guide to Paper');
    });

    test('the back of a page is the text the search holds', () async {
      final pages = PdfPages.open(await documentBytes(kPressLease));
      final lines = pages.linesOf(0);
      expect(lines.first, 'EQUIPMENT LEASE AGREEMENT');
      expect(lines.length, greaterThan(20));
    });

    test('the words a page holds are counted onto the store', () async {
      final store = await storeFor(kFieldGuide);
      final pages = PdfPages.open(
        await documentBytes(kFieldGuide),
        onPageRun: store.recordPageWords,
      );
      expect(store.wordCount, 0);
      pages.runNext(1, 1);
      expect(store.wordCount, greaterThan(100));
    });

    test('a rung is chosen for every page before anything is painted', () async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      for (var page = 0; page < pages.pageCount; page++) {
        pages.run(page);
        expect(pages.pageAt(page).plan, RenderPlan.rich);
      }
    });

    testWidgets('a file with no page tree is torn paper, never a blank sheet', (
      tester,
    ) async {
      final pages = PdfPages.open(Uint8List.fromList(const <int>[1, 2, 3, 4]));
      expect(pages.pageCount, 0);
      expect(pages.runNext(0, 5), isNull);
      expect(PdfLayout.of(pages, kSheetWidth).extent, 0);
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _readerApp(store, pages));
      expect(find.byType(TornPage), findsOneWidget);
      expect(find.text(kDocumentUnreadableLabel), findsOneWidget);
    });

    testWidgets('a page image is decoded off the paint path', (tester) async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      pages.run(5);
      expect(pages.pageAt(5).list!.images, hasLength(1));
      expect(pages.pageAt(5).images, isEmpty);
      await tester.runAsync(() async {
        await pages.decodeImages(5);
      });
      final decoded = pages.pageAt(5).images.values.single;
      expect(decoded.width, 600);
      expect(decoded.height, 400);
      pages.dispose();
    });
  });

  group('what each rung draws', () {
    testWidgets('a page nobody has run yet shimmers, and is never blank', (
      tester,
    ) async {
      await _pumpPage(tester, _renderOf(null, RenderPlan.rich));
      expect(find.byType(PageShimmer), findsOneWidget);
      // The rectangle is already the page's own, so nothing moves when the
      // words arrive.
      expect(
        tester.getSize(find.byType(PageShimmer)),
        Size(kSheetWidth, kSheetWidth * 792 / 612),
      );
    });

    testWidgets('rich paints text, paths and images in one pass', (
      tester,
    ) async {
      await _pumpPage(tester, _renderOf(richPage(), RenderPlan.rich));
      expect(find.byType(PageShimmer), findsNothing);
      expect(find.byType(UnsupportedImageBox), findsNothing);
      expect(_painterOf(tester), isA<PageListPainter>());
    });

    testWidgets('an image this reader cannot decode leaves its rect behind', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _renderOf(textWithUndecodableImagePage(), RenderPlan.textOnly),
      );
      expect(find.byType(UnsupportedImageBox), findsOneWidget);
      expect(find.text(kImageLabel), findsOneWidget);
      // 72 to 300 of a 612 wide page, drawn onto a 372 wide sheet.
      final box = tester.getRect(find.byType(UnsupportedImageBox));
      expect(box.left, closeTo(72 * kSheetWidth / 612, 0.01));
      expect(box.width, closeTo(228 * kSheetWidth / 612, 0.01));
    });

    testWidgets('a scan this reader cannot read says so on a card', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        _renderOf(scanPage(encoding: 'jbig2'), RenderPlan.scanUnreadable),
      );
      expect(find.byType(ScanCard), findsOneWidget);
      expect(find.text('SCANNED PAGE'), findsOneWidget);
      expect(find.text('This page is a picture.'), findsOneWidget);
      expect(find.text('Nothing on it can be read or found.'), findsOneWidget);
      expect(tester.getSize(find.byType(ScanCard)).width, kScanCardWidth);
    });

    testWidgets('a readable scan is the picture itself, with no card', (
      tester,
    ) async {
      late final ui.Image picture;
      await tester.runAsync(() async {
        picture = await _solidImage();
      });
      await _pumpPage(
        tester,
        _renderOf(
          scanPage(),
          RenderPlan.scan,
          images: <String, ui.Image>{'Im0': picture},
        ),
      );
      expect(find.byType(ScanCard), findsNothing);
      expect(find.byType(PageShimmer), findsNothing);
      picture.dispose();
    });

    testWidgets('a scan whose picture has not arrived shimmers, never white', (
      tester,
    ) async {
      await _pumpPage(tester, _renderOf(scanPage(), RenderPlan.scan));
      expect(find.byType(PageShimmer), findsOneWidget);
    });

    testWidgets('a page that will not interpret is torn, not blank', (
      tester,
    ) async {
      await _pumpPage(tester, _renderOf(null, RenderPlan.damaged));
      expect(find.byType(TornPage), findsOneWidget);
      expect(find.text(kPageDamagedLabel), findsOneWidget);
      expect(find.byType(PageShimmer), findsNothing);
    });

    testWidgets('every page carries its own folio, printed in its corner', (
      tester,
    ) async {
      await _pumpPage(tester, _renderOf(richPage(), RenderPlan.rich, index: 3));
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('the body in the shell', () {
    testWidgets('the chip counts pages before a single one is run', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      final body = PdfBody(
        store: store,
        pages: PdfPages.open(await documentBytes(kFieldGuide)),
      );
      expect(body.unitCount, 6);
      expect(body.positionLabel, '1 / 6');
      expect(body.foreEdgeMarks, hasLength(6));
      expect(body.foreEdgeMarks.first, 0);
      expect(body.foreEdgeMarks.last, 1);
    });

    testWidgets('scrolling the block moves the reader through it', (
      tester,
    ) async {
      final store = await _pumpReader(tester);
      expect(store.position, 0);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
      await tester.pump();
      expect(store.position, 1);
    });

    testWidgets('a scrub lands the block on the page it names', (tester) async {
      final store = await _pumpReader(tester);
      store.position = 4;
      await tester.pump();
      await tester.pump();
      final scroll = tester.widget<Scrollable>(find.byType(Scrollable).first);
      expect(scroll.controller!.offset, greaterThan(1800));
    });
  });

  group('its goldens', () {
    testWidgets('reader__loading', (tester) async {
      final store = await storeFor(kFieldGuide);
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      // One frame only. The page tree has been walked, so the chip is already
      // right, and nothing has been interpreted, which is what the sheet
      // draws while it waits.
      tester.view.physicalSize = kPhone.logical * kDpr;
      tester.view.devicePixelRatio = kDpr;
      const padding = FakeViewPadding(top: 62 * kDpr, bottom: 34 * kDpr);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_readerApp(store, pages));
      await capture(tester, 'reader__loading');
      await settle(tester);
    });

    testWidgets('reader__pdf_page', (tester) async {
      await _pumpReader(tester);
      await capture(tester, 'reader__pdf_page');
    });

    testWidgets('reader__pdf_chrome_hidden', (tester) async {
      await _pumpReader(tester);
      final gesture = await tester.startGesture(
        const Offset(kScreenWidth / 2, 400),
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.up();
      await settle(tester);
      await capture(tester, 'reader__pdf_chrome_hidden');
    });

    testWidgets('reader__pdf_dogeared', (tester) async {
      final store = await _pumpReader(tester);
      store.toggleDogEar(0);
      await tester.pump();
      await settle(tester);
      await capture(tester, 'reader__pdf_dogeared');
    });
  });
}

/// One page's worth of state, without a file behind it, so a rung can be
/// judged on its own.
PdfPageRender _renderOf(
  PageDisplayList? list,
  RenderPlan plan, {
  int index = 0,
  Map<String, ui.Image> images = const <String, ui.Image>{},
}) {
  return PdfPageRender(
    index: index,
    size: const Size(612, 792),
    plan: plan,
    list: list,
    runs: list == null ? const <LaidOutRun>[] : mergeRuns(list.texts),
    images: images,
  );
}

/// One decoded pixel, which is all a page needs to count as having a picture.
/// It must be called inside `tester.runAsync`.
Future<ui.Image> _solidImage() {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(const <int>[0x33, 0x33, 0x33, 0xFF]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<void> _pumpPage(WidgetTester tester, PdfPageRender page) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Align(
        alignment: Alignment.topLeft,
        child: PdfPageView(page: page, width: kSheetWidth, shimmer: 0.4),
      ),
    ),
  );
}

CustomPainter? _painterOf(WidgetTester tester) {
  for (final widget in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (widget.painter is PageListPainter) return widget.painter;
  }
  return null;
}

Widget _readerApp(DocumentStore store, PdfPages pages) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderScreen(
    store: store,
    bodyBuilder: (context) => PdfBody(store: store, pages: pages),
  ),
);

/// The field guide open in the reader, with its first pages already run.
Future<DocumentStore> _pumpReader(WidgetTester tester) async {
  final store = await storeFor(kFieldGuide);
  final pages = PdfPages.open(await documentBytes(kFieldGuide));
  await pumpScreen(tester, _readerApp(store, pages));
  await tester.runAsync(() async {
    await pages.decodeImages(0);
  });
  await settle(tester);
  return store;
}
