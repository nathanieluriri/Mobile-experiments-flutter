import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/helpers/fold_geometry.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/back_layer.dart';
import 'package:quire/screens/reader/bodies/page_states.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/bodies/prose_body.dart';
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// A phrase from the second page of the field guide, far enough down that
/// page's text layer to land inside the region a half turned corner has torn
/// away.
const String kRevealedPhrase = 'Tear a narrow strip from a scrap';

void main() {
  group('what a fold uncovers', () {
    testWidgets('the torn region carries the page own words', (tester) async {
      final (store, pages) = await _pumpPdfReader(tester, kFieldGuide);
      await _toPage(tester, 1);
      expect(store.position, 1);

      final gesture = await _peelHalfWay(tester);
      final point = _foldPoint(tester);
      expect(point, isNotNull);

      // The back is in the tree at all only because a corner is open, and the
      // only place the sheet puts it is inside the torn clip.
      expect(find.byType(PdfTextBack), findsOneWidget);
      final revealed = _revealedLines(tester, point!);
      expect(revealed, isNotEmpty);
      expect(revealed.any((line) => line.contains(kRevealedPhrase)), isTrue);
      // Every word uncovered came off this page, not out of the app.
      expect(pages.linesOf(1), containsAll(revealed));

      await gesture.up();
      await settle(tester);
    });

    testWidgets('the back is built before the corner has moved a point', (
      tester,
    ) async {
      final (store, pages) = await _pumpPdfReader(tester, kFieldGuide);
      expect(pages.extracted(store.position), isTrue);
      // The page after the current one too, because a fold can be finished in
      // either direction from the page it starts on.
      expect(pages.extracted(store.position + 1), isTrue);
      // And not the whole document, which would make the loading band a lie.
      expect(pages.extracted(pages.pageCount - 1), isFalse);
    });

    testWidgets('a page evicted from the cache keeps the back it earned', (
      tester,
    ) async {
      final pages = PdfPages.open(await documentBytes(kFieldGuide));
      pages.run(0);
      expect(pages.holds(0), isTrue);
      for (var page = 1; page < pages.pageCount; page++) {
        pages.run(page);
      }
      // Filling a cache of twelve takes more pages than this file has, so the
      // point is stated directly: lines outlive the display list they came
      // off, because the back of a sheet is not evictable.
      expect(pages.extracted(0), isTrue);
      expect(pages.heldLinesOf(0), isNotEmpty);
      pages.dispose();
    });

    testWidgets('a page with no text layer says so, and is never blank', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      final pages = PdfPages.open(pageWithoutTextLayer());
      expect(pages.pageCount, 1);
      await pumpScreen(tester, _readerApp(store, pages));
      await settle(tester);

      final gesture = await _peelHalfWay(tester);
      expect(find.byType(NoTextLayerBack), findsOneWidget);
      expect(find.text(kNoTextLayer), findsOneWidget);
      await gesture.up();
      await settle(tester);
      pages.dispose();
    });
  });

  group('the other two bodies', () {
    testWidgets('a Markdown back is its own source, read off the parse', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      final body = ProseBody(
        store: store,
        document: store.document!,
        source: 'A line of the file itself.',
      );
      await _pumpFace(tester, body.buildBack);
      expect(find.byType(SourceBack), findsOneWidget);
      expect(find.text('A line of the file itself.'), findsOneWidget);
    });

    testWidgets('a file that parsed to nothing says so on both faces', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      final body = ProseBody(
        store: store,
        document: const QuireDocument(
          title: '',
          sections: <DocSection>[DocSection('', <DocBlock>[])],
          sourceFormat: 'md',
        ),
        // Whitespace only, which is what an empty Markdown file decodes to.
        source: '   ',
      );
      for (final face in <WidgetBuilder>[body.buildFront, body.buildBack]) {
        await _pumpFace(tester, face);
        expect(find.byType(TornPage), findsOneWidget);
        expect(find.text(kDocumentEmptyLabel), findsOneWidget);
      }
    });

    testWidgets('a grid with no rows says so rather than showing paper', (
      tester,
    ) async {
      final store = DocumentStore(entryFor(kSubscribers))
        ..loadFrom(Uint8List(0));
      final body = SheetBody(store: store);
      for (final face in <WidgetBuilder>[body.buildFront, body.buildBack]) {
        await _pumpFace(tester, face);
        expect(find.byType(TornPage), findsOneWidget);
        expect(find.text(kDocumentEmptyLabel), findsOneWidget);
      }
    });
  });
}

/// The bundled file open in the real reader, with its first pages already run.
Future<(DocumentStore, PdfPages)> _pumpPdfReader(
  WidgetTester tester,
  String fileName,
) async {
  final store = await storeFor(fileName);
  final pages = PdfPages.open(await documentBytes(fileName));
  await pumpScreen(tester, _readerApp(store, pages));
  await settle(tester);
  return (store, pages);
}

Widget _readerApp(DocumentStore store, PdfPages pages) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderScreen(
    store: store,
    bodyBuilder: (context) => PdfBody(store: store, pages: pages),
  ),
);

/// Puts one face of a body on screen at sheet size, so a test can read the
/// back without turning anything over.
Future<void> _pumpFace(WidgetTester tester, WidgetBuilder face) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: SizedBox(
          width: kSheetWidth,
          height: kSheetHeight,
          child: Builder(builder: face),
        ),
      ),
    ),
  );
}

/// Scrolls the page block until the reader is standing on [page].
Future<void> _toPage(WidgetTester tester, int page) async {
  for (var i = 0; i < page; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
    await tester.pump();
  }
  await settle(tester);
}

/// Holds the corner until the fold arms, then carries it far enough that the
/// tear is most of the sheet, and leaves the finger down.
Future<TestGesture> _peelHalfWay(WidgetTester tester) async {
  final gesture = await tester.startGesture(sheetCornerHandle());
  await pumpMs(tester, 160);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(const Offset(-33, -33));
    await pumpMs(tester, 16);
  }
  return gesture;
}

Offset? _foldPoint(WidgetTester tester) =>
    tester.widget<SheetSurface>(find.byType(SheetSurface)).foldPoint;

/// Every line of the back that the tear has actually uncovered.
///
/// It is measured against the same geometry the clipper uses, so it answers
/// the only question worth asking about a fold: is there anything to read in
/// the part of the sheet the corner just took away.
List<String> _revealedLines(WidgetTester tester, Offset point) {
  final geometry = computeFoldGeometry(
    kSheetWidth,
    kSheetHeight,
    point.dx,
    point.dy,
    corner: Corner.bottomRight,
  );
  final torn = Path()..addPolygon(geometry.clipped, true);
  final lines = find.descendant(
    of: find.byType(PdfTextBack),
    matching: find.byType(Text),
  );
  final out = <String>[];
  for (var i = 0; i < lines.evaluate().length; i++) {
    final at = lines.at(i);
    final rect = tester.getRect(at).shift(-kSheetRect.topLeft);
    if (torn.contains(rect.center)) out.add(tester.widget<Text>(at).data ?? '');
  }
  return out;
}
