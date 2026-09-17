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
import 'package:quire/screens/reader/bodies/sheet_geometry.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/bodies/sheet_tabs.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('how a spreadsheet names itself', () {
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
    testWidgets('a workbook opens on its first sheet', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      expect(find.byType(SheetTabs), findsOneWidget);
      expect(find.byType(ParseStrip), findsNothing);
      expect(find.byType(SheetGrid), findsOneWidget);
      expect(SheetController.of(store).sheet, 0);
    });

    testWidgets('a CSV carries the strip instead of the tabs', (tester) async {
      final store = await storeFor(kSubscribers);
      await _pumpSheet(tester, store);
      expect(find.byType(SheetTabs), findsNothing);
      expect(find.byType(ParseStrip), findsOneWidget);
      expect(find.text('CSV · COMMA · 70 ROWS · 6 COLUMNS'), findsOneWidget);
    });

    testWidgets('tapping a cell rings it and raises the bar', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      expect(find.byType(CellBar), findsNothing);

      await tester.tapAt(_cellCentre(tester, store, row: 2, column: 1));
      await settle(tester);
      expect(SheetController.of(store).selected, const SheetCell(2, 1));
      expect(find.byType(CellBar), findsOneWidget);
      expect(find.text('Runs!B3'), findsOneWidget);
    });

    testWidgets('the bar prints the formula a cell was worked out by', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      // Chosen rather than tapped: G is off the right of the phone until the
      // grid is pushed, and what is being tested here is the bar.
      SheetController.of(store).selected = const SheetCell(2, 6);
      await settle(tester);
      expect(find.text('Runs!G3'), findsOneWidget);
      // Printed the way the spreadsheet itself writes it, after an equals sign.
      expect(find.text('=D3*E3+F3'), findsOneWidget);
    });

    testWidgets('the bar leaves when the reader pushes the grid', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tapAt(_cellCentre(tester, store, row: 2, column: 1));
      await settle(tester);
      expect(find.byType(CellBar), findsOneWidget);

      await tester.drag(
        find.byType(SheetGrid),
        const Offset(0, -120),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(SheetController.of(store).selected, isNull);
      expect(find.byType(CellBar), findsNothing);
    });

    testWidgets('switching sheets changes the grid', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tap(find.text('Paper').last);
      await settle(tester);
      expect(SheetController.of(store).sheet, 1);
      await capture(tester, 'reader__sheet_second');
    });

    testWidgets('pushing the grid moves the reader down the document', (
      tester,
    ) async {
      final store = await storeFor(kSubscribers);
      await _pumpSheet(tester, store);
      expect(store.position, 0);

      await tester.drag(
        find.byType(SheetGrid),
        const Offset(0, -kGridRowHeight * 10),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(store.position, 10);
      expect(store.positionLabel, '11 / 71');
    });

    testWidgets('the back of a sheet holds the formulas, not the values', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: _Back(store: store),
        ),
      );
      await settle(tester);
      await capture(tester, 'reader__sheet_back');
    });
  });

  group('the sheets of a workbook', () {
    testWidgets('the fill travels from one sheet to the next', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tap(find.text('Paper').last);
      await tester.pump();
      await pumpMs(tester, kTabTravel.inMilliseconds ~/ 2);
      await capture(tester, 'sheet__tabs_travelling');
      await settle(tester);
      expect(SheetController.of(store).sheet, 1);
    });

    testWidgets('every sheet is a tap away, whatever the foot can show', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);

      await tester.tap(find.bySemanticsLabel('Every sheet in this workbook'));
      await settle(tester);
      expect(find.text('Sheets'), findsOneWidget);
      await capture(tester, 'sheet__all_sheets');

      await tester.tap(find.text('Summary').last);
      await settle(tester);
      expect(SheetController.of(store).sheet, 2);
    });
  });

  group('finding in a spreadsheet', () {
    testWidgets('rings the cell it found and takes the grid across to it', (
      tester,
    ) async {
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
      // A total, which lives in column G, off the right of the phone.
      await tester.enterText(find.byType(EditableText).last, '589.00');
      await settle(tester);

      final chosen = SheetController.of(store).selected;
      expect(chosen, isNotNull, reason: 'the match is ringed');
      expect(chosen!.column, 6);
      expect(find.text('Runs!G3'), findsOneWidget);
      await capture(tester, 'sheet__found');
    });
  });

  group('the goldens', () {
    testWidgets('reader__sheet_xlsx', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await capture(tester, 'reader__sheet_xlsx');
    });

    testWidgets('reader__sheet_tabs', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      await tester.tap(find.text('Paper').last);
      await settle(tester);
      await capture(tester, 'reader__sheet_tabs');
    });

    testWidgets('reader__sheet_cell_bar', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpSheet(tester, store);
      SheetController.of(store).selected = const SheetCell(2, 6);
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

/// The middle of a cell on screen, worked out from the sheet's own geometry,
/// since a file states its own column widths and row heights and the grid
/// draws them as stated.
Offset _cellCentre(
  WidgetTester tester,
  DocumentStore store, {
  required int row,
  required int column,
}) {
  final table = store.document!.sections[SheetController.of(store).sheet].blocks
      .whereType<TableBlock>()
      .first;
  final geometry = SheetGeometry.of(table);
  final grid = tester.getRect(find.byType(SheetGrid));
  return grid.topLeft +
      Offset(
        kRowHeaderWidth + geometry.leftOf(column) + geometry.widthOf(column) / 2,
        kGridHeaderHeight + geometry.topOf(row) + geometry.heightOf(row) / 2,
      );
}

/// A CSV whose rows do not all match its header, so the strip has something
/// to count.
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
