import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/number_format.dart';
import 'package:quire/format/xlsx_parser.dart'
    show XlsxParser, kIndexedColours, xlsxToDocument;
import 'package:quire/model/document.dart';
import 'package:quire/painting/cell_goo_painter.dart';
import 'package:quire/painting/grid_painter.dart';
import 'package:quire/painting/tab_goo_painter.dart';
import 'package:quire/screens/reader/bodies/cell_bar.dart';
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/bodies/sheet_geometry.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

const _main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// A workbook of [sheets], each a worksheet's XML body, with [styles] and,
/// for the sheet at [commentOn], a comment on A1.
Uint8List _book(
  List<(String, String)> sheets, {
  String styles = '',
  int? commentOn,
}) {
  final zip = Archive();
  void add(String name, String xml) {
    final bytes = utf8.encode(xml);
    zip.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="rels"
    ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
</Types>''');
  add('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$_pkg">
  <Relationship Id="rId1" Target="xl/workbook.xml" Type="$_rel/officeDocument"/>
</Relationships>''');
  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="$_main" xmlns:r="$_rel"><sheets>
${[for (var i = 0; i < sheets.length; i++) '<sheet name="${sheets[i].$1}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join('\n')}
</sheets></workbook>''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$_pkg">
${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Target="worksheets/sheet${i + 1}.xml" Type="$_rel/worksheet"/>'].join('\n')}
</Relationships>''');
  if (styles.isNotEmpty) {
    add('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="$_main">$styles</styleSheet>''');
  }
  for (var i = 0; i < sheets.length; i++) {
    add('xl/worksheets/sheet${i + 1}.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_main">${sheets[i].$2}</worksheet>''');
    if (commentOn == i) {
      add('xl/worksheets/_rels/sheet${i + 1}.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$_pkg">
  <Relationship Id="rId1" Target="../comments${i + 1}.xml" Type="$_rel/comments"/>
</Relationships>''');
      add('xl/comments${i + 1}.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<comments xmlns="$_main"><authors><author>Ada</author></authors>
<commentList><comment ref="A1" authorId="0"><text><t>Argued over.</t></text>
</comment></commentList></comments>''');
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

String _rows(int count, {int columns = 3}) =>
    '<sheetData>${[
      for (var r = 1; r <= count; r++) '<row r="$r">${[for (var c = 0; c < columns; c++) '<c r="${String.fromCharCode(65 + c)}$r" t="inlineStr"><is><t>${String.fromCharCode(65 + c)}$r</t></is></c>'].join()}</row>',
    ].join()}</sheetData>';

DocumentStore _store(Uint8List bytes) =>
    DocumentStore(entryFor(kPressRunCosts))..loadFrom(bytes);

Future<void> _pumpBody(WidgetTester tester, DocumentStore store) => pumpScreen(
  tester,
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ReaderScreen(
      store: store,
      bodyBuilder: (context) => SheetBody(store: store),
    ),
  ),
);

Future<void> _pumpHost(WidgetTester tester, DocumentStore store) => pumpScreen(
  tester,
  MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ReaderHost(store: store),
  ),
);

GridPainter _body(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GridPainter>()
    .where((painter) => painter.pane == GridPane.cells)
    .last;

/// Where the top left of the sheet's cells is on the glass: where the pane
/// of cells is on screen, less how far the sheet has been pushed inside it.
Offset _cellsOnGlass(WidgetTester tester) {
  final painter = _body(tester);
  final pane = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && identical(widget.painter, painter),
  );
  return tester.getTopLeft(pane) - painter.offset;
}

void main() {
  group('choosing a cell keeps the reader in place', () {
    testWidgets('a header in a frozen row moves nothing', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpBody(tester, store);
      await settle(tester);
      await tester.drag(
        find.byType(SheetGrid),
        const Offset(-120, -240),
        warnIfMissed: false,
      );
      await settle(tester);
      final before = _body(tester).offset;
      // Row 2 is frozen: its client header is on screen however far down
      // the sheet has been pushed.
      SheetController.of(store).selected = const SheetCell(1, 1);
      await settle(tester);
      expect(_body(tester).offset.dy, before.dy);
    });

    testWidgets('a cell in the last row comes up clear of the bar', (
      tester,
    ) async {
      final store = await storeFor(kSubscribers);
      await _pumpBody(tester, store);
      await settle(tester);
      for (var i = 0; i < 4; i++) {
        await tester.drag(
          find.byType(SheetGrid),
          const Offset(0, -700),
          warnIfMissed: false,
        );
        await settle(tester);
      }
      final table = store.document!.sections.first.blocks
          .whereType<TableBlock>()
          .first;
      final last = table.rows.length - 1;
      SheetController.of(store).selected = SheetCell(last, 1);
      await settle(tester);
      final geometry = SheetGeometry.of(table);
      final grid = tester.getRect(find.byType(SheetGrid));
      final painter = _body(tester);
      final bottom =
          grid.top +
          kGridHeaderHeight +
          geometry.frozenHeight +
          geometry.topOf(last + 1) -
          painter.offset.dy;
      final bar = tester.getRect(find.byType(CellBar));
      expect(bottom, lessThanOrEqualTo(bar.top + 1));
    });
  });

  group('the lock', () {
    testWidgets('holds the sheets bar too', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpBody(tester, store);
      await settle(tester);
      store.lock = ReaderLock.page;
      await settle(tester);
      await tester.tap(find.text('Paper').last, warnIfMissed: false);
      await settle(tester);
      expect(SheetController.of(store).sheet, 0);
    });
  });

  group('the sheets bar', () {
    testWidgets('brings the sheet showing into view', (tester) async {
      final store = _store(
        _book(<(String, String)>[
          for (var i = 1; i <= 12; i++) ('Quarter $i ledger', _rows(3)),
        ]),
      );
      await _pumpBody(tester, store);
      await settle(tester);
      SheetController.of(store).sheet = 10;
      await settle(tester);
      final pill = tester.getRect(find.text('Quarter 11 ledger').last);
      expect(pill.left, greaterThanOrEqualTo(0));
      expect(pill.right, lessThanOrEqualTo(kPhone.logical.width));
    });

    testWidgets('a third sheet on the way sets off without stopping', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpBody(tester, store);
      await settle(tester);
      TabGooPainter goo() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<TabGooPainter>()
          .single;
      Offset where() {
        final painter = goo();
        return TabGooPainter.bodyAt(
          from: painter.from,
          to: painter.to,
          t: painter.t,
          viscous: true,
        ).center;
      }

      await tester.tap(find.text('Paper').last);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.tap(find.text('Summary').last);
      await tester.pump();
      final start = where();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Moving again within a few frames, not held still to gather first.
      expect((where() - start).distance, greaterThan(0.5));
    });

    test(
      'the fill opens as it arrives rather than stopping, then bursting',
      () {
        const from = Rect.fromLTWH(10, 7, 60, 30);
        const to = Rect.fromLTWH(160, 7, 90, 30);
        var widest = 0.0;
        var last = 0.0;
        for (var frame = 0; frame <= 42; frame++) {
          final body = TabGooPainter.bodyAt(
            from: from,
            to: to,
            t: frame / 42,
            viscous: true,
          );
          if (frame / 42 >= kTabGooTravelEnd) {
            widest = math.max(widest, (body.width - last).abs());
          }
          last = body.width;
        }
        expect(widest, lessThan(12));
      },
    );
  });

  group('find', () {
    testWidgets('put away, lights nothing', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpHost(tester, store);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).last, 'Thornbury');
      await settle(tester);
      expect(
        tester.widget<SheetGrid>(find.byType(SheetGrid)).matches,
        isNotEmpty,
      );
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(tester.widget<SheetGrid>(find.byType(SheetGrid)).matches, isEmpty);
    });
  });

  group('comments', () {
    testWidgets('are listed across the workbook and go to their sheet', (
      tester,
    ) async {
      final store = _store(
        _book(<(String, String)>[
          ('Plain', _rows(4)),
          ('Argued', _rows(4)),
        ], commentOn: 1),
      );
      await _pumpHost(tester, store);
      await settle(tester);
      await tester.tap(
        find.bySemanticsLabel('What can be done with this document'),
      );
      await settle(tester);
      await tester.tap(find.text('Comments'));
      await settle(tester);
      expect(find.text('Argued over.'), findsOneWidget);
      await tester.tap(find.text('Argued over.'));
      await settle(tester);
      final sheet = SheetController.of(store);
      expect(sheet.sheet, 1);
      expect(sheet.selected, const SheetCell(0, 0));
    });
  });

  group('a flick', () {
    testWidgets('is caught by a touch, and the touch chooses nothing', (
      tester,
    ) async {
      final store = await storeFor(kSubscribers);
      await _pumpBody(tester, store);
      await settle(tester);
      await tester.fling(
        find.byType(SheetGrid),
        const Offset(0, -300),
        2500,
        warnIfMissed: false,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.tap(find.byType(SheetGrid), warnIfMissed: false);
      await tester.pump();
      // Measured on the glass, since the band the flick sent away is still
      // leaving and the letters are going up with it over rows that hold
      // still.
      final caught = _cellsOnGlass(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_cellsOnGlass(tester).dx, closeTo(caught.dx, 0.01));
      expect(_cellsOnGlass(tester).dy, closeTo(caught.dy, 0.01));
      expect(SheetController.of(store).selected, isNull);
    });
  });

  group('what the whole sheet does together', () {
    testWidgets('a hop between a frozen header and the body flows', (
      tester,
    ) async {
      const frozen =
          '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
          'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>';
      final store = _store(
        _book(<(String, String)>[('Long', '$frozen${_rows(150)}')]),
      );
      await _pumpBody(tester, store);
      await settle(tester);
      // A header row that is frozen, and the body pushed a long way down.
      final grid = find.byType(SheetGrid);
      for (var i = 0; i < 3; i++) {
        await tester.drag(grid, const Offset(0, -800), warnIfMissed: false);
        await settle(tester);
      }
      final sheet = SheetController.of(store);
      sheet.selected = const SheetCell(80, 1);
      await settle(tester);
      sheet.selected = const SheetCell(0, 1);
      await tester.pump();
      CellGooPainter? goo() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<CellGooPainter>()
          .firstOrNull;
      Offset? last;
      var litBefore = _body(tester).litStrength;
      for (var frame = 0; frame < 90; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final body = goo()?.goo.body.center;
        if (body != null && last != null) {
          expect((body - last).distance, lessThan(40), reason: 'frame $frame');
        }
        last = body ?? last;
        final lit = _body(tester).litStrength;
        expect((lit - litBefore).abs(), lessThan(0.12), reason: 'frame $frame');
        litBefore = lit;
        final painter = _body(tester);
        // A ring still at full strength is never a shrunken square.
        if (painter.ring != null && painter.ringStrength > 0.9) {
          expect(painter.ring!.width, greaterThan(60), reason: 'frame $frame');
        }
      }
    });

    testWidgets('a find wash fades in and out', (tester) async {
      Widget app(Set<SheetCell> matches) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: AppColors.ground,
          child: SheetGrid(
            table: TableBlock(<DocRow>[
              DocRow(<DocCell>[
                DocCell(<DocBlock>[
                  ParagraphBlock(<DocSpan>[DocSpan('found')]),
                ]),
              ]),
            ], grid: true),
            selected: null,
            matches: matches,
            onSelect: (_) {},
          ),
        ),
      );
      await pumpScreen(tester, app(const <SheetCell>{}));
      await settle(tester);
      final seen = <double>[];
      await pumpScreen(tester, app(<SheetCell>{const SheetCell(0, 0)}));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(_body(tester).matchStrength);
      }
      await pumpScreen(tester, app(const <SheetCell>{}));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(_body(tester).matchStrength);
      }
      for (var i = 1; i < seen.length; i++) {
        expect((seen[i] - seen[i - 1]).abs(), lessThan(0.25), reason: '$i');
      }
      expect(seen[29], greaterThan(0.95));
      expect(seen.last, lessThan(0.05));
    });

    testWidgets('turning sheet while the last one coasts keeps the reader', (
      tester,
    ) async {
      final store = _store(
        _book(<(String, String)>[
          ('First', _rows(200)),
          ('Second', _rows(200)),
        ]),
      );
      await _pumpBody(tester, store);
      await settle(tester);
      await tester.fling(
        find.byType(SheetGrid),
        const Offset(0, -300),
        3000,
        warnIfMissed: false,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final sheet = SheetController.of(store);
      sheet.sheet = 1;
      await tester.pump(const Duration(milliseconds: 48));
      sheet.selected = const SheetCell(3, 1);
      await settle(tester);
      expect(sheet.sheet, 1);
      expect(sheet.selected, const SheetCell(3, 1));
      expect(store.position, greaterThanOrEqualTo(200));
    });

    testWidgets('the bar reads a rounded number as it is stored', (
      tester,
    ) async {
      final store = _store(
        _book(
          <(String, String)>[
            (
              'Pi',
              '<sheetData><row r="1"><c r="A1" s="1"><v>3.14159265358979</v>'
                  '</c></row></sheetData>',
            ),
          ],
          styles:
              '<numFmts count="1"><numFmt numFmtId="164" formatCode="0.00"/>'
              '</numFmts><fonts count="1"><font/></fonts>'
              '<fills count="1"><fill/></fills>'
              '<cellXfs count="2"><xf/><xf numFmtId="164"/></cellXfs>',
        ),
      );
      await _pumpBody(tester, store);
      await settle(tester);
      SheetController.of(store).selected = const SheetCell(0, 0);
      await settle(tester);
      expect(
        tester.widget<CellBar>(find.byType(CellBar)).value,
        '3.14159265358979',
      );
    });

    test('a number format gives its colour to the value it colours', () {
      expect(formatColour(-5, '0.00;[Red]0.00'), 0xFFFF0000);
      expect(formatColour(5, '0.00;[Red]0.00'), isNull);
      expect(
        formatColour(-5, '[Blue]0;[Color10]0', palette: kIndexedColours),
        kIndexedColours[17],
      );
    });

    testWidgets('find goes back to a match it has already been to', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await _pumpHost(tester, store);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).last, 'Little Ouse');
      await settle(tester);
      final sheet = SheetController.of(store);
      final found = sheet.selected;
      expect(found, isNotNull);
      await tester.drag(
        find.byType(SheetGrid),
        const Offset(0, 600),
        warnIfMissed: false,
      );
      await settle(tester);
      expect(sheet.selected, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(sheet.selected, found);
    });
  });

  group('what a cell looks like', () {
    test('wrapped words and where they sit are read', () {
      final bytes = _book(
        <(String, String)>[
          (
            'Notes',
            '<sheetData><row r="1" ht="60" customHeight="1">'
                '<c r="A1" s="1" t="inlineStr"><is><t>A long note that the '
                'author wrapped</t></is></c></row></sheetData>',
          ),
        ],
        styles:
            '<fonts count="1"><font/></fonts><fills count="1"><fill/></fills>'
            '<cellXfs count="2"><xf/><xf applyAlignment="1">'
            '<alignment wrapText="1" vertical="top"/></xf></cellXfs>',
      );
      final table = xlsxToDocument(
        XlsxParser(bytes).parse(),
        'Notes',
      ).sections.single.blocks.whereType<TableBlock>().single;
      final cell = cellAt(table, 0, 0)!;
      expect(cell.wrap, isTrue);
      expect(cell.verticalAlign, DocVerticalAlign.top);
    });

    testWidgets(
      'words on a dark fill are set light, and a red flag stays red',
      (tester) async {
        DocCell cell(String text, {int? fill, int? colour}) =>
            DocCell(<DocBlock>[
              ParagraphBlock(<DocSpan>[DocSpan(text, color: colour)]),
            ], background: fill);
        final table = TableBlock(<DocRow>[
          DocRow(<DocCell>[
            cell('Region', fill: 0xFF1F4E78, colour: 0xFFFFFFFF),
            cell('Total', fill: 0xFF000000),
            cell('Paper', fill: 0xFFF6F1E7),
          ]),
          DocRow(<DocCell>[
            cell('Late', colour: 0xFFC00000),
            cell('Black ink', colour: 0xFF000000),
            DocCell(
              <DocBlock>[
                ParagraphBlock(<DocSpan>[
                  DocSpan(
                    'A note that the author wrapped onto three lines of a tall '
                    'row, set at its top',
                  ),
                ]),
              ],
              wrap: true,
              verticalAlign: DocVerticalAlign.top,
            ),
          ], height: 60),
        ], grid: true);
        await pumpScreen(
          tester,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: AppColors.ground,
              child: SheetGrid(table: table, selected: null, onSelect: (_) {}),
            ),
          ),
        );
        await settle(tester);
        await capture(tester, 'sheet__grid_inks');
      },
    );

    test('numbers in a text format, and nought in accounting', () {
      expect(formatCell(12.5, '@'), '12.5');
      expect(
        formatCell(
          0,
          r'_-"£"* #,##0.00_-;\-"£"* #,##0.00_-;_-"£"* "-"??_-;_-@_-',
        ),
        '£-',
      );
    });
  });
}
