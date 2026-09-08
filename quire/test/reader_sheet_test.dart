import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/csv_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/painting/spine_glyph_painter.dart';
import 'package:quire/screens/reader/bodies/cell_bar.dart';
import 'package:quire/screens/reader/bodies/parse_strip.dart';
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/bodies/sheet_tabs.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the geometry a spine table is laid out on', () {
    test('the bundled sheets fill the sheet exactly', () {
      // Section 6.4 names these results, and they are what makes the table a
      // static composition rather than something that has to be measured.
      final runs = columnWidths(9);
      expect(runs.open, 236);
      expect(runs.spine, 12);
      expect(kRowHeaderWidth + runs.open + 8 * runs.spine, kSheetWidth);

      final paper = columnWidths(6);
      expect(paper.open, 272);
      expect(paper.spine, 12);
      expect(kRowHeaderWidth + paper.open + 5 * paper.spine, kSheetWidth);

      final summary = columnWidths(3);
      expect(summary.open, 276);
      expect(summary.spine, 28);
      expect(kRowHeaderWidth + summary.open + 2 * summary.spine, kSheetWidth);
    });

    test('columns are lettered the way a spreadsheet letters them', () {
      expect(columnLetter(0), 'A');
      expect(columnLetter(8), 'I');
      expect(columnLetter(25), 'Z');
      expect(columnLetter(26), 'AA');
      expect(columnLetter(27), 'AB');
      expect(columnLetter(51), 'AZ');
      expect(columnLetter(52), 'BA');
    });

    test('a cell reference names its sheet, its letter and its file row', () {
      expect(cellReference('Runs', 6, 2), 'Runs!G3');
      expect(cellReference('Summary', 1, 13), 'Summary!B14');
    });

    test('a sheet that fits never scrolls sideways', () {
      final widths = spineWidths(9, open: 6);
      expect(widths[6], 236);
      expect(widths[0], 12);
      expect(openOffset(widths, 6), 0);
    });

    test('a sheet too wide for the phone scrolls exactly its overflow', () {
      // Section 6.4's worked hypothetical: 30 columns give open 160 and spine
      // 12, a total of 548, which is 176 wider than the sheet.
      final wide = columnWidths(30);
      expect(wide.open, 160);
      expect(wide.spine, 12);
      final widths = spineWidths(30, open: 0);
      expect(widths.reduce((a, b) => a + b), 508);
      expect(openOffset(widths, 29), 176);
    });
  });

  group('what a cell says', () {
    test('a cell holding a newline is flattened to one line', () {
      expect(
        flattenCell('Two addresses on file:\nsummer at the lake house'),
        'Two addresses on file: summer at the lake house',
      );
      expect(flattenCell('a\r\nb'), 'a b');
      expect(flattenCell('  spaced \t out  '), 'spaced out');
      expect(flattenCell(''), '');
    });

    testWidgets('every cell in the real CSV survives being flattened', (
      tester,
    ) async {
      final doc = await parsedDocument(kSubscribers);
      final table = doc.sections.first.blocks.first as TableBlock;
      var wrapped = 0;
      for (final row in table.rows) {
        for (final cell in row.cells) {
          if (cell.text.contains('\n')) wrapped++;
          expect(flattenCell(cell.text).contains('\n'), isFalse);
        }
      }
      expect(wrapped, 2, reason: 'the file has two cells with a newline in it');
    });
  });

  group('the value glyphs a folded column carries', () {
    test('a bar never disappears and never overruns its spine', () {
      expect(spineBarWidth(0), 1);
      expect(spineBarWidth(0.05), 1);
      expect(spineBarWidth(0.5), 5);
      expect(spineBarWidth(1), kSpineBarMax);
      expect(spineBarWidth(4), kSpineBarMax);
    });

    testWidgets('numbers become bars, text becomes dots', (tester) async {
      final doc = await parsedDocument(kPressRunCosts);
      final runs = doc.sections.first.blocks.first as TableBlock;
      final quantity = spineValuesFor(runs, 3, from: 2);
      expect(quantity.length, runs.rows.length - 2);
      expect(quantity.every((v) => v.mark == SpineMark.bar), isTrue);
      expect(quantity.map((v) => v.extent).reduce((a, b) => a > b ? a : b), 1);
      // The longest run on the sheet is 4,000 sheets, so the first job's 1,200
      // draws three tenths of a full bar.
      expect(quantity.first.extent, closeTo(1200 / 4000, 0.0001));

      final jobCode = spineValuesFor(runs, 0, from: 2);
      expect(jobCode.every((v) => v.mark == SpineMark.dot), isTrue);
    });

    testWidgets('a matched cell keeps its glyph and changes its colour', (
      tester,
    ) async {
      final doc = await parsedDocument(kPressRunCosts);
      final runs = doc.sections.first.blocks.first as TableBlock;
      final found = spineValuesFor(
        runs,
        0,
        from: 2,
        matches: <SheetCell>{const SheetCell(4, 0)},
      );
      expect(found[2].found, isTrue);
      expect(found[2].mark, SpineMark.dot);
      expect(found[1].found, isFalse);
    });
  });

  group('what the parse strip counts', () {
    testWidgets('the real CSV is comma delimited and not ragged', (
      tester,
    ) async {
      final facts = csvFacts(readCsv(await documentBytes(kSubscribers)));
      expect(facts.delimiter, 'COMMA');
      expect(facts.rows, 70);
      expect(facts.columns, 6);
      expect(facts.raggedRows, isEmpty);
      expect(facts.line, 'CSV · COMMA · 70 ROWS · 6 COLUMNS');
    });

    test('a ragged file is counted, not repaired in the dark', () {
      final facts = csvFacts(readCsv(_raggedCsv()));
      expect(facts.rows, 6);
      expect(facts.columns, 5);
      expect(facts.raggedRows, <int>{2, 4, 6});
      expect(facts.firstRagged, 2);
    });

    test('the delimiter is named, never printed as punctuation', () {
      expect(delimiterName(','), 'COMMA');
      expect(delimiterName(';'), 'SEMICOLON');
      expect(delimiterName('\t'), 'TAB');
      expect(delimiterName('|'), 'PIPE');
    });
  });

  group('the sheet body on screen', () {
    testWidgets('a workbook opens on its first sheet with column A open', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      expect(find.byType(SheetTabs), findsOneWidget);
      expect(find.byType(ParseStrip), findsNothing);
      expect(SheetController.of(store).sheet, 0);
      expect(SheetController.of(store).openColumn, 0);
      expect(find.text('Job code'), findsOneWidget);
      expect(find.text('QP-2601-01'), findsOneWidget);
    });

    testWidgets('a CSV carries the strip instead of the tabs', (tester) async {
      final store = await storeFor(kSubscribers);
      await _pumpSheet(tester, store);
      expect(find.byType(SheetTabs), findsNothing);
      expect(find.byType(ParseStrip), findsOneWidget);
      expect(find.text('CSV · COMMA · 70 ROWS · 6 COLUMNS'), findsOneWidget);
    });

    testWidgets('tapping a spine opens it and folds the old column away', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await settle(tester);
      expect(SheetController.of(store).openColumn, 6);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('QP-2601-01'), findsNothing);
    });

    testWidgets('tapping a cell rings it and raises the bar', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await settle(tester);
      expect(find.byType(CellBar), findsNothing);
      await tester.tapAt(const Offset(200, 223));
      await settle(tester);
      expect(SheetController.of(store).selected, const SheetCell(2, 6));
      expect(find.byType(CellBar), findsOneWidget);
      expect(find.text('Runs!G3'), findsOneWidget);
      expect(find.text('D3*E3+F3'), findsOneWidget);
    });

    testWidgets('the bar leaves when the reader scrolls the grid', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(const Offset(160, 223));
      await settle(tester);
      expect(find.byType(CellBar), findsOneWidget);
      await tester.drag(find.byType(SpineTable), const Offset(0, -120));
      await settle(tester);
      expect(find.byType(CellBar), findsNothing);
      expect(SheetController.of(store).selected, isNull);
    });

    testWidgets('switching sheets changes the grid and the underline', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tap(find.text('Paper'));
      await settle(tester);
      expect(SheetController.of(store).sheet, 1);
      expect(find.text('Stock name'), findsOneWidget);
      expect(find.text('Abbey Cream Wove'), findsWidgets);
    });

    testWidgets('scrolling the grid moves the reader down the document', (
      tester,
    ) async {
      final store = await storeFor(kSubscribers);
      await _pumpSheet(tester, store);
      expect(store.position, 0);
      await tester.drag(find.byType(SpineTable), _tenRows);
      await settle(tester);
      expect(store.position, 10);
      expect(store.positionLabel, '11 / 71');
    });

    testWidgets('a cell with a newline in it still stands one row tall', (
      tester,
    ) async {
      final store = await storeFor(kSubscribers);
      // The wrapped cell is in Notes, the last column, so it has to be the
      // open one before there is anything to measure.
      SheetController.of(store).openColumn = 5;
      await _pumpSheet(tester, store);
      await tester.drag(find.byType(SpineTable), _tenRows);
      await settle(tester);
      final cell = find.textContaining('Two addresses on file');
      expect(cell, findsOneWidget);
      expect(tester.getSize(cell).height, lessThanOrEqualTo(kTableRowHeight));
    });

    testWidgets('the back of a sheet holds the formulas, not the values', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      SheetController.of(store).openColumn = 6;
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: kSheetWidth,
              height: kSheetHeight,
              child: _Back(store: store),
            ),
          ),
        ),
      );
      expect(find.text('=D3*E3+F3'), findsOneWidget);
      expect(find.text('£589.00'), findsNothing);
    });
  });

  group('the goldens', () {
    testWidgets('reader__sheet_xlsx', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await capture(tester, 'reader__sheet_xlsx');
    });

    testWidgets('reader__sheet_column_open', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await settle(tester);
      await capture(tester, 'reader__sheet_column_open');
    });

    testWidgets('reader__sheet_tabs', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tap(find.text('Paper'));
      await settle(tester);
      await capture(tester, 'reader__sheet_tabs');
    });

    testWidgets('reader__sheet_cell_bar', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await settle(tester);
      await tester.tapAt(const Offset(200, 223));
      await settle(tester);
      await capture(tester, 'reader__sheet_cell_bar');
    });

    testWidgets('reader__csv', (tester) async {
      final store = await storeFor(kSubscribers);
      await _pumpSheet(tester, store);
      await capture(tester, 'reader__csv');
    });

    testWidgets('reader__csv_ragged', (tester) async {
      final store = DocumentStore(entryFor(kSubscribers))
        ..loadFrom(_raggedCsv());
      await _pumpSheet(tester, store);
      expect(find.text('3 RAGGED'), findsOneWidget);
      await capture(tester, 'reader__csv_ragged');
    });

    testWidgets('column__t0000', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await pumpMs(tester, 0);
      await capture(tester, 'column__t0000');
    });

    testWidgets('column__t0240', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_spineCentre(6));
      await pumpMs(tester, 0);
      await pumpMs(tester, 240);
      await capture(tester, 'column__t0240');
    });
  });
}

/// The reader, holding a grid document, at the phone's size.
Future<void> _pumpSheet(WidgetTester tester, DocumentStore store) async {
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => SheetBody(store: store),
      ),
    ),
  );
}

/// A drag that scrolls the grid exactly ten rows.
///
/// The first stretch of any drag is spent on the touch slop and never reaches
/// the list, so the distance asked for is ten rows plus that slop.
const Offset _tenRows = Offset(0, -(10 * kTableRowHeight + kDragSlopDefault));

/// The middle of spine [column] on the Runs sheet, in screen coordinates,
/// while column A is the open one.
Offset _spineCentre(int column) {
  final widths = spineWidths(9, open: 0);
  var x = kSheetLeft + kRowHeaderWidth;
  for (var c = 0; c < column; c++) {
    x += widths[c];
  }
  return Offset(x + widths[column] / 2, 300);
}

/// A small CSV whose last three rows do not match its header.
///
/// The bundled file is clean, so raggedness needs a file of its own rather
/// than a damaged copy of a real one.
Uint8List _raggedCsv() => Uint8List.fromList(
  utf8.encode(
    'Town,Copies,Tier,Note\n'
    'Ardenhollow,12,Folio,Left at the gate\n'
    'Kilnbarrow,4,Quarto\n'
    'Mereveld,9,Octavo,Second copy for the shop\n'
    'Vaux-la-Pierre,3\n'
    'Halyard,7,Patron,Ship flat\n'
    'Fen Ditton,2,Folio,Held,Extra field\n',
  ),
);

/// The back of a sheet, on its own, so a test can read what the fold would
/// have shown without performing the fold.
class _Back extends StatelessWidget {
  const _Back({required this.store});

  final DocumentStore store;

  @override
  Widget build(BuildContext context) =>
      SheetBody(store: store).buildBack(context);
}
