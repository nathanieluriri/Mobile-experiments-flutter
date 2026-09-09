import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/model/document.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/screens/reader/back_layer.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the corner region', () {
    testWidgets('a hold then a drag peels the corner', (tester) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      final gesture = await longPressAndDrag(
        tester,
        sheetCornerHandle(),
        sheetCornerHandle() - const Offset(180, 180),
        holdMs: 160,
      );
      expect(_foldPoint(tester), isNotNull);
      expect(_scrollOffset(), 0);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('a quick drag from the corner scrolls instead', (tester) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      final gesture = await dragAndHold(
        tester,
        sheetCornerHandle(),
        sheetCornerHandle() - const Offset(0, 240),
      );
      expect(_foldPoint(tester), isNull);
      expect(_scrollOffset(), greaterThan(0));
      await gesture.up();
      await settle(tester);
    });

    testWidgets('a hold in the middle of the sheet never peels', (
      tester,
    ) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      final gesture = await longPressAndDrag(
        tester,
        const Offset(200, 400),
        const Offset(80, 260),
        holdMs: 400,
      );
      expect(_foldPoint(tester), isNull);
      await gesture.up();
      await settle(tester);
    });

    testWidgets('a peel short of the commit distance springs home', (
      tester,
    ) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      final gesture = await longPressAndDrag(
        tester,
        sheetCornerHandle(),
        sheetCornerHandle() - const Offset(90, 90),
        holdMs: 160,
      );
      await gesture.up();
      await settle(tester);
      expect(_side(tester), SheetSide.front);
    });
  });

  group('the rest of the sheet', () {
    testWidgets(
      'a scroll takes the chrome out of the way, a tap brings it back',
      (tester) async {
        await _pumpReader(tester, back: const SizedBox.expand());
        expect(_chromeHidden(tester), 0);
        final gesture = await dragAndHold(
          tester,
          const Offset(200, 500),
          const Offset(200, 340),
        );
        await gesture.up();
        await settle(tester);
        expect(_chromeHidden(tester), 1);
        await tester.tapAt(const Offset(200, 400));
        await settle(tester);
        expect(_chromeHidden(tester), 0);
      },
    );

    testWidgets('a scroll under six points leaves the chrome alone', (
      tester,
    ) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      final gesture = await dragAndHold(
        tester,
        const Offset(200, 500),
        const Offset(200, 480),
        steps: 20,
      );
      await gesture.up();
      await settle(tester);
      expect(_chromeHidden(tester), 0);
    });
  });

  group('the flip', () {
    testWidgets('past the commit distance the sheet turns over', (
      tester,
    ) async {
      await _pumpReader(tester, back: const SizedBox.expand());
      await _flipOver(tester);
      expect(_side(tester), SheetSide.back);
      expect(find.text('· BACK'), findsOneWidget);
    });

    testWidgets('flip keyframes', (tester) async {
      // The real reader on a real page file, front and back, because the whole
      // claim of the fold is that the corner uncovers this page's own words.
      // A stand in on either face would let a keyframe photograph an empty
      // wedge for ever without anything failing.
      await _pumpPdfReader(tester, kPressLease);
      final gesture = await tester.startGesture(sheetCornerHandle());
      await pumpMs(tester, 160);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-33, -33));
        await pumpMs(tester, 16);
      }
      await gesture.up();
      await tester.pump();
      await capture(tester, 'flip__t0000');
      await pumpMs(tester, 190);
      await capture(tester, 'flip__t0190');
      await pumpMs(tester, 190);
      // The sweep ends on this frame, so one more zero length pump lets the
      // sheet land on its back without moving the clock.
      await tester.pump();
      await capture(tester, 'flip__t0380');
      await settle(tester);
    });
  });

  group('the back of the page', () {
    testWidgets('reader__back_pdf', (tester) async {
      final lines = await _pdfLines(kPressLease, 0);
      expect(lines, isNotEmpty);
      await _pumpReader(
        tester,
        title: 'Press Lease',
        back: PdfTextBack(lines: lines),
      );
      await _flipOver(tester);
      await capture(tester, 'reader__back_pdf');
    });

    testWidgets('reader__back_pdf_no_text', (tester) async {
      await _pumpReader(
        tester,
        title: 'Press Lease',
        back: const NoTextLayerBack(),
      );
      await _flipOver(tester);
      await capture(tester, 'reader__back_pdf_no_text');
    });

    testWidgets('reader__back_markdown', (tester) async {
      final source = utf8.decode(await documentBytes(kBinderyNotes));
      await _pumpReader(
        tester,
        title: 'Bindery Notes',
        back: SourceBack(source: source),
      );
      await _flipOver(tester);
      await capture(tester, 'reader__back_markdown');
    });

    testWidgets('reader__back_sheet', (tester) async {
      final document = await parsedDocument(kPressRunCosts);
      final table = document.sections.first.blocks
          .whereType<TableBlock>()
          .first;
      await _pumpReader(
        tester,
        title: 'Press Run Costs',
        back: GridBack(table: table),
      );
      await _flipOver(tester);
      await capture(tester, 'reader__back_sheet');
    });
  });
}

/// The merged runs of one page of a bundled PDF, which is exactly the text the
/// search index holds and exactly what the back of that page shows.
Future<List<String>> _pdfLines(String fileName, int page) async {
  final pdf = PdfFile.open(await documentBytes(fileName));
  final list = ContentInterpreter(pdf).run(pdf.pages[page]);
  return mergeRuns(list.texts).map((run) => run.text).toList();
}

/// Peels the corner past the commit distance, lets go, and lets the sheet
/// finish turning over.
Future<void> _flipOver(WidgetTester tester) async {
  final gesture = await tester.startGesture(sheetCornerHandle());
  await pumpMs(tester, 160);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(const Offset(-33, -33));
    await pumpMs(tester, 16);
  }
  await gesture.up();
  await settle(tester);
}

/// How far the chrome has left, read from the band the shell actually drew.
double _chromeHidden(WidgetTester tester) =>
    tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden;

Offset? _foldPoint(WidgetTester tester) =>
    tester.widget<SheetSurface>(find.byType(SheetSurface)).foldPoint;

SheetSide _side(WidgetTester tester) =>
    tester.widget<SheetSurface>(find.byType(SheetSurface)).side;

final ScrollController _controller = ScrollController();

double _scrollOffset() => _controller.hasClients ? _controller.offset : 0;

Future<DocumentStore> _pumpReader(
  WidgetTester tester, {
  required Widget back,
  String title = 'Field Guide To Paper',
}) async {
  final store = DocumentStore(
    LibraryEntry(
      assetPath: 'assets/documents/field-guide-to-paper.pdf',
      title: title,
      format: DocFormat.pdf,
      bytes: 313458,
    ),
  )..pdfPageCount = 6;
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => _StubBody(store: store, back: back),
      ),
    ),
  );
  return store;
}

/// The bundled page file open in the real reader, with the pages around the
/// one it opens on already read.
Future<DocumentStore> _pumpPdfReader(
  WidgetTester tester,
  String fileName,
) async {
  final store = await storeFor(fileName);
  final pages = PdfPages.open(await documentBytes(fileName));
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => PdfBody(store: store, pages: pages),
      ),
    ),
  );
  await settle(tester);
  return store;
}

/// A column of real paragraphs, so a fold has something to show through and a
/// flip has something to hide.
const _front = '''
Paper has a grain, and the grain runs the long way of the sheet it was made on.
Fold with the grain and the crease is clean. Fold across it and the fibres tear
rather than bend, which is why a badly cut book will not open flat.

A leaf is two pages. The front is what the document shows you, and the back is
what the document actually holds: the text a machine can read, the values behind
the formatting, the source under the rendering.

Turning the sheet over is the whole vocabulary of this reader. Pause halfway
through and the corner catches instead, which is a bookmark, and it is the same
gesture separated only by whether you stopped moving.

The fore edge is the other half of the argument. A page block seen from the
side is a map of the whole document, drawn at the scale of the document itself,
and a thumb laid against it moves through the file at the speed of paper rather
than at the speed of a scroll bar.

None of this asks a reader to learn anything. A corner that lifts under a
finger is a corner that lifts under a finger, and a stack of pages seen edge on
is a stack of pages seen edge on. The whole vocabulary was already in the
object.''';

/// A body of prose that fills the sheet, standing in for a real format.
class _StubBody extends ReaderBody {
  const _StubBody({required this.store, required this.back});

  final DocumentStore store;
  final Widget back;

  @override
  Widget buildFront(BuildContext context) => SingleChildScrollView(
    controller: _controller,
    padding: const EdgeInsets.all(26),
    child: Text(_front, style: AppText.pageBody.copyWith(color: AppColors.ink)),
  );

  @override
  Widget buildBack(BuildContext context) => back;

  @override
  int get unitCount => store.unitCount;

  @override
  String get positionLabel => store.positionLabel;

  @override
  List<double> get foreEdgeMarks => <double>[
    for (var i = 0; i < store.unitCount; i++)
      i / (store.unitCount - 1).clamp(1, double.infinity),
  ];
}
