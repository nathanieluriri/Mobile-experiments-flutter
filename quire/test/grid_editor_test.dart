import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/csv_patch.dart';
import 'package:quire/format/csv_parser.dart';
import 'package:quire/screens/edit/edit_frame.dart';
import 'package:quire/screens/edit/grid_editor.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));
String _s(Uint8List b) => utf8.decode(b);

void main() {
  group('a CSV file changed cell by cell', () {
    test('with nothing changed is the file that was read', () async {
      final bytes = await documentBytes(kSubscribers);
      final doc = CsvDocument.read(bytes);
      expect(doc.write(), same(bytes));
    });

    test('reads the same cells the reader shows', () async {
      final bytes = await documentBytes(kSubscribers);
      final doc = CsvDocument.read(bytes);
      final table = readCsv(bytes);
      expect(doc.rowCount, table.rows.length);
      for (var r = 0; r < table.rows.length; r++) {
        for (var c = 0; c < table.rows[r].length; c++) {
          expect(doc.cell(r, c), table.rows[r][c]);
        }
      }
    });

    test('a changed cell changes its own line and no other', () {
      const text = 'name,note,amount\r\n"Ada","says ""hi""",1\r\nBo,plain,2\r\n';
      final doc = CsvDocument.read(_b(text))..setCell(2, 1, 'now, with a comma');
      expect(
        _s(doc.write()),
        'name,note,amount\r\n"Ada","says ""hi""",1\r\nBo,"now, with a comma",2\r\n',
      );
    });

    test('a quoted cell stays quoted and quotes inside are doubled', () {
      final doc = CsvDocument.read(_b('"a","b"\n"c","d"\n'))..setCell(1, 1, 'say "x"');
      expect(_s(doc.write()), '"a","b"\n"c","say ""x"""\n');
    });

    test('keeps the byte order mark and the tab of a TSV', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a\tb\n1\t2\n')]);
      final doc = CsvDocument.read(bytes)..setCell(1, 0, '9');
      expect(doc.delimiter, '\t');
      expect(doc.write(), [0xEF, 0xBB, 0xBF, ...utf8.encode('a\tb\n9\t2\n')]);
    });

    test('a file with no last newline gets none when a row is added', () {
      final doc = CsvDocument.read(_b('a,b\n1,2'))..setCell(2, 0, '3');
      expect(_s(doc.write()), 'a,b\n1,2\n3,');
    });

    test('a new column is added to every row that has cells', () {
      final doc = CsvDocument.read(_b('a,b\n1,2\n\n3,4\n'))..setCell(0, 2, 'c');
      expect(_s(doc.write()), 'a,b,c\n1,2,\n\n3,4,\n');
    });

    test('rows and columns go in and come out', () {
      final doc = CsvDocument.read(_b('a,b\n1,2\n3,4\n'))
        ..insertRow(1)
        ..insertColumn(1);
      expect(_s(doc.write()), 'a,,b\n,,\n1,,2\n3,,4\n');
      doc
        ..deleteColumn(1)
        ..deleteRow(1);
      expect(_s(doc.write()), 'a,b\n1,2\n3,4\n');
      doc.deleteRow(2);
      expect(_s(doc.write()), 'a,b\n1,2\n');
    });

    test('deleting the last row of a file with no last newline keeps it so', () {
      final doc = CsvDocument.read(_b('a\nb\nc'))..deleteRow(2);
      expect(_s(doc.write()), 'a\nb');
    });

    test('a cell holding a line break comes back whole', () {
      const text = 'a,b\n"two\nlines",x\n';
      final doc = CsvDocument.read(_b(text));
      expect(doc.cell(1, 0), 'two\nlines');
      doc.setCell(1, 1, 'y');
      expect(_s(doc.write()), 'a,b\n"two\nlines",y\n');
    });

    test('UTF-16 is written back as UTF-16', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xFE,
        for (final u in 'a;b\n1;2\n'.codeUnits) ...[u & 0xff, u >> 8],
      ]);
      final doc = CsvDocument.read(bytes)..setCell(1, 1, 'é');
      expect(doc.encoding, CsvEncoding.utf16le);
      expect(doc.delimiter, ';');
      final out = doc.write();
      expect(out.sublist(0, 2), [0xFF, 0xFE]);
      expect(CsvDocument.read(out).cell(1, 1), 'é');
    });

    test('a single-byte file stays Windows-1252 until a character it cannot hold is typed', () {
      final bytes = Uint8List.fromList(latin1.encode('a,b\ncafé,1\n'));
      final doc = CsvDocument.read(bytes)..setCell(1, 1, 'crème €5');
      expect(doc.encoding, CsvEncoding.windows1252);
      expect(doc.write(), [...latin1.encode('a,b\ncafé,crème '), 0x80, ...latin1.encode('5\n')]);
      doc.setCell(1, 1, 'Łódź');
      expect(doc.write(), [0xEF, 0xBB, 0xBF, ...utf8.encode('a,b\ncafé,Łódź\n')]);
    });

    test('a Windows-1252 file keeps its curly quotes and euro signs in rows nobody touched', () {
      final bytes = Uint8List.fromList([
        ...latin1.encode('Item,Price,Note\r\nCoffee,2.50 '), 0x80, ...latin1.encode(',Barista'), 0x92,
        ...latin1.encode('s pick\r\nTea,1.80 '), 0x80, ...latin1.encode(',plain\r\n'),
      ]);
      final doc = CsvDocument.read(bytes);
      expect(doc.cell(1, 2), 'Barista\u2019s pick');
      doc.setCell(2, 2, 'Grandma\u2019s');
      final out = doc.write();
      final firstRows = bytes.sublist(0, bytes.indexOf(0x54));
      expect(out.sublist(0, firstRows.length), firstRows);
      expect(CsvDocument.read(out).cell(2, 2), 'Grandma\u2019s');
    });

    List<List<String>> cellsOf(CsvDocument doc) => [
          for (var r = 0; r < doc.rowCount; r++) [for (var c = 0; c < doc.rows[r].cells.length; c++) doc.cell(r, c)],
        ];

    test('a row added after a last row left inside an open quote is a row of its own', () {
      for (final grow in <void Function(CsvDocument)>[
        (doc) => doc
          ..setCell(3, 0, 'Eraser')
          ..setCell(3, 1, '2.00'),
        (doc) => doc
          ..insertRow(doc.rowCount)
          ..setCell(doc.rowCount - 1, 0, 'Eraser'),
      ]) {
        final doc = CsvDocument.read(_b('item,price\nPen,1.00\nPencil,"\n'));
        grow(doc);
        final out = doc.write();
        expect(readCsv(out).rows, cellsOf(doc));
        expect(CsvDocument.read(out).rowCount, doc.rowCount);
      }
    });

    test('a byte that is not UTF-8 in a file with a byte order mark is kept in rows nobody touched', () {
      final bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF, ...ascii.encode('name,city\r\nZo'), 0xEB, ...ascii.encode(',Paris\r\nBo,Hull\r\n'),
      ]);
      final doc = CsvDocument.read(bytes)..setCell(2, 1, 'York');
      expect(doc.write(), [
        0xEF, 0xBB, 0xBF, ...ascii.encode('name,city\r\nZo'), 0xEB, ...ascii.encode(',Paris\r\nBo,York\r\n'),
      ]);
    });

    test('a saved file reads back with the cells the editor showed', () {
      final cases = <(String, void Function(CsvDocument))>[
        ('Artikel;Preis\r\nApfel;1,50\r\nBirne;2,30\r\nKiwi;0,99\r\n', (d) => d.setCell(0, 1, 'Preis, EUR')),
        ('Artikel;Preis\r\nApfel;1,50\r\nBirne;2,30\r\nKiwi;0,99\r\n', (d) => d.deleteRow(0)),
        ('name\tnote\nAda\thi, there\nBo\tyes, please\n', (d) => d.deleteColumn(0)),
        ('email\nada@example.com\nbo@example.com\n', (d) => d.setCell(0, 0, 'email; primary')),
      ];
      for (final (text, edit) in cases) {
        final doc = CsvDocument.read(_b(text));
        edit(doc);
        final back = readCsv(doc.write());
        expect(back.rows, cellsOf(doc), reason: text);
        if (doc.columnCount > 1) expect(back.delimiter, doc.delimiter, reason: text);
      }
    });

    test('deleting the last row leaves the line ending of the row before it', () {
      final doc = CsvDocument.read(_b('a,b\r\n1,2\r\n3,4\n'))..deleteRow(2);
      expect(_s(doc.write()), 'a,b\r\n1,2\r\n');
    });

    test('a bare CR before a blank line does not swallow the blank line', () {
      final doc = CsvDocument.read(_b('a\rb\r\n\nc\n'))..deleteRow(1);
      expect(CsvDocument.read(doc.write()).rowCount, doc.rowCount);
      expect(readCsv(doc.write()).rows.length, doc.rowCount);
    });

    test('a UTF-16 file keeps an odd last byte', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xFE,
        for (final u in 'a,b\r\n1,2\r\n'.codeUnits) ...[u & 0xff, u >> 8],
        0x41,
      ]);
      final out = (CsvDocument.read(bytes)..setCell(1, 0, '9')).write();
      expect(out.last, 0x41);
      expect(out.length, bytes.length);
    });

    test('a Latin-1 file whose remaining bytes would read as UTF-8 still reads back the same', () {
      final bytes = Uint8List.fromList(latin1.encode('name,note\nCAF\u00C9\u0085,x\nZo\u00EB,y\n'));
      final doc = CsvDocument.read(bytes)..setCell(2, 0, 'Zoe');
      final again = CsvDocument.read(doc.write());
      expect(again.cell(1, 0), CsvDocument.read(bytes).cell(1, 0));
      expect(again.cell(2, 0), 'Zoe');
    });

    test('a saved file keeps reading back with its own delimiter', () {
      final cases = <(String, void Function(CsvDocument))>[
        ('Name\tAddress\nAda\t12 High St, Leeds\nBo\t4 Low Rd, Hull\nCy\t9 Mill Ln, York\n', (d) => d.setCell(0, 1, 'Address, town')),
        ('date,qty,price,notes\n2024-01-02,3,4.50,"pens; paper"\n2024-01-03,1,12.00,"ink; nibs"\n2024-01-04,2,7.25,"card; glue"\n', (d) => d.deleteRow(0)),
        ('Nr.;Nachname, Vorname;Ort\r\n1;Müller, Hans;Berlin\r\n2;Schmidt, Anna;Hamburg\r\n3;Weber, Klaus;München\r\n', (d) => d.deleteColumn(2)),
        ('Name;Ort\r\nMüller, Hans;Berlin\r\nSchmidt, Anna;Hamburg\r\n', (d) => d.setCell(0, 1, 'Ort, PLZ')),
        ('a;b\n\n1;2\n3;4\n', (d) => d.deleteRow(0)),
        ('Name;Ort\nMüller;Berlin\nNachtrag, siehe unten\nWeber;Bonn\n', (d) => d.deleteColumn(1)),
      ];
      for (final (text, edit) in cases) {
        final doc = CsvDocument.read(_b(text));
        edit(doc);
        final back = readCsv(doc.write());
        final cells = cellsOf(doc);
        expect(back.rows.length, cells.length, reason: text);
        for (var r = 0; r < cells.length; r++) {
          if (cells[r].every((c) => c.isEmpty)) continue;
          expect(back.rows[r], cells[r], reason: '$text row $r');
        }
        if (doc.columnCount > 1) expect(back.delimiter, doc.delimiter, reason: text);
      }
    });

    test('a new column leaves blank lines blank and short rows short', () {
      final doc = CsvDocument.read(_b('a,b,c\n1,2\n\n3,4,5\n6\n'))..insertColumn(0);
      expect(_s(doc.write()), ',a,b,c\n,1,2\n\n,3,4,5\n,6\n');
      // An empty column at the right edge is nothing a file can hold.
      final wide = CsvDocument.read(_b('a,b,c\n1,2\n\n3,4,5\n6\n'))..insertColumn(3);
      expect(_s(wide.write()), 'a,b,c\n1,2\n\n3,4,5\n6\n');
      wide.setCell(0, 3, 'd');
      expect(_s(wide.write()), 'a,b,c,d\n1,2\n\n3,4,5,\n6\n');
    });

    test('a row whose one cell is emptied stays a row', () {
      final doc = CsvDocument.read(_b('email\nada@example.com\nbo@example.com\n'))..setCell(2, 0, '');
      expect(_s(doc.write()), 'email\nada@example.com\n""\n');
    });

    test('typing past the edge and clearing it again leaves the file as it was', () {
      final bytes = _b('a,b\n1,2\nBo\n3,4\n');
      final doc = CsvDocument.read(bytes)
        ..setCell(1, 4, 'oops')
        ..setCell(1, 4, '')
        ..setCell(9, 0, 'far')
        ..setCell(9, 0, '');
      expect(doc.changed, isFalse);
      expect(doc.write(), same(bytes));
    });

    test('putting a cell back as it was is not a change to write', () {
      final bytes = _b('a,b\n1,2\n');
      final doc = CsvDocument.read(bytes)
        ..setCell(1, 0, '5')
        ..setCell(1, 0, '1');
      expect(doc.changed, isFalse);
      expect(doc.write(), same(bytes));
    });
  });

  group('the grid', () {
    Uint8List? saved;

    Future<GridEditorState> open(WidgetTester tester, Uint8List bytes) async {
      saved = null;
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: GridEditor(
            title: 'Subscribers',
            bytes: bytes,
            onBack: () {},
            onSave: (out, note) async {
              saved = out;
              return null;
            },
          ),
        ),
      );
      await settle(tester);
      return tester.state<GridEditorState>(find.byType(GridEditor));
    }

    Offset cellAt(WidgetTester tester, GridEditorState state, int row, int column) {
      final body = tester.getTopLeft(find.byKey(const ValueKey<String>('grid-body')));
      final column0 = tester.getTopLeft(find.byKey(const ValueKey<String>('column-0')));
      final head = tester.getTopLeft(find.byKey(ValueKey<String>('column-$column')));
      final width = tester.getSize(find.byKey(ValueKey<String>('column-$column'))).width;
      return Offset(
        body.dx + (head.dx - column0.dx) + width / 2,
        body.dy + row * kGridRowHeight + kGridRowHeight / 2,
      );
    }

    String reference(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const ValueKey<String>('grid-reference'))).data!;

    testWidgets('a tap picks a cell and the bar shows where and what it is', (tester) async {
      final state = await open(tester, _b('name,city\nAda,Leeds\nBo,Hull\n'));
      await tester.tapAt(cellAt(tester, state, 1, 1));
      await settle(tester);
      expect(reference(tester), 'B2');
      expect(find.text('Leeds'), findsWidgets);
      expect(state.editing, isFalse);
    });

    testWidgets('two quick taps open a cell; Enter keeps it and moves down', (tester) async {
      final state = await open(tester, _b('name,city\nAda,Leeds\nBo,Hull\n'));
      await tester.tapAt(cellAt(tester, state, 1, 1));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(cellAt(tester, state, 1, 1));
      await settle(tester);
      expect(state.editing, isTrue);
      await tester.enterText(find.byType(EditableText).first, 'York');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(state.document.cell(1, 1), 'York');
      expect(reference(tester), 'B3');
      expect(state.editing, isTrue);
      await tester.tap(find.text('SAVE'));
      await settle(tester);
      expect(_s(saved!), 'name,city\nAda,York\nBo,Hull\n');
    });

    testWidgets('a picked cell tapped again offers cut, copy, paste and clear', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n'));
      await tester.tapAt(cellAt(tester, state, 1, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(cellAt(tester, state, 1, 0));
      await settle(tester);
      for (final label in ['Cut', 'Copy', 'Paste', 'Clear']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Clear'));
      await settle(tester);
      expect(state.document.cell(1, 0), '');
      await tester.tap(find.bySemanticsLabel('Undo'));
      await settle(tester);
      expect(state.document.cell(1, 0), '1');
      await tester.tap(find.bySemanticsLabel('Redo'));
      await settle(tester);
      expect(state.document.cell(1, 0), '');
    });

    testWidgets('copy in one cell and paste in another', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return null;
      });
      final state = await open(tester, _b('a,b\n1,2\n'));
      Future<void> menuOn(int row, int column) async {
        await tester.tapAt(cellAt(tester, state, row, column));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tapAt(cellAt(tester, state, row, column));
        await settle(tester);
      }

      await menuOn(0, 1);
      await tester.tap(find.text('Copy'));
      await settle(tester);
      await menuOn(1, 0);
      await tester.tap(find.text('Paste'));
      await settle(tester);
      expect(state.document.cell(1, 0), 'b');
    });

    testWidgets('a row number offers rows to insert above and below, and delete', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n3,4\n'));
      await tester.tap(find.byKey(const ValueKey<String>('row-1')));
      await settle(tester);
      expect(reference(tester), 'Row 2');
      await tester.tap(find.text('Insert below'));
      await settle(tester);
      expect(state.document.rowCount, 4);
      expect(state.document.cell(2, 0), '');
      expect(state.document.cell(3, 0), '3');
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(state.document.rowCount, 3);
    });

    testWidgets('a column letter offers columns to insert left and right', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n'));
      await tester.tap(find.byKey(const ValueKey<String>('column-1')));
      await settle(tester);
      await tester.tap(find.text('Insert left'));
      await settle(tester);
      expect(state.document.cell(0, 2), 'b');
      expect(state.document.cell(0, 1), '');
    });

    testWidgets('typing below the last row adds a row', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n'));
      await tester.tapAt(cellAt(tester, state, 3, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(cellAt(tester, state, 3, 0));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'new');
      await tester.tap(find.bySemanticsLabel('Keep'));
      await settle(tester);
      expect(state.document.rowCount, 4);
      expect(_s(state.document.write()), 'a,b\n1,2\n,\nnew,\n');
    });

    Future<void> quickTaps(WidgetTester tester, Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await settle(tester);
    }

    testWidgets('picking a long value never moves the grid, so a double tap opens that cell', (tester) async {
      final long = List.filled(12, 'a long note that wraps').join(' ');
      final state = await open(tester, _b('a,b\n1,$long\n2,short\n'));
      final top = tester.getTopLeft(find.byKey(const ValueKey<String>('grid-body'))).dy;
      final cell = cellAt(tester, state, 1, 1);
      await tester.tapAt(cell);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(find.byKey(const ValueKey<String>('grid-body'))).dy, top);
      await tester.tapAt(cell);
      await settle(tester);
      expect(reference(tester), 'B2');
      expect(state.editing, isTrue);
    });

    testWidgets('typing at the end of a long value shows the words and the caret', (tester) async {
      final long = List.filled(6, 'a long note that wraps').join(' ');
      final state = await open(tester, _b('a,b\n1,$long\n'));
      await quickTaps(tester, cellAt(tester, state, 1, 1));
      tester.testTextInput.enterText('$long every week');
      await settle(tester);
      final field = find.descendant(of: find.byKey(const ValueKey<String>('grid-field')), matching: find.byType(EditableText));
      final box = tester.getRect(field);
      final editable = tester.renderObject<RenderEditable>(
        find.descendant(of: field, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Editable')),
      );
      final caret = editable.getLocalRectForCaret(editable.selection!.extent);
      final shown = MatrixUtils.transformRect(editable.getTransformTo(null), caret);
      expect(box.contains(shown.center), isTrue, reason: '$shown in $box');
      expect(box.height, greaterThanOrEqualTo(AppText.bodyTight.fontSize! * 1.2));
    });

    testWidgets('a touch stops the grid sliding and picks nothing', (tester) async {
      final rows = [for (var r = 0; r < 400; r++) [for (var c = 0; c < 30; c++) 'r$r c$c'].join(',')].join('\n');
      final state = await open(tester, _b('$rows\n'));
      await tester.flingFrom(cellAt(tester, state, 12, 1), const Offset(0, -400), 4000);
      await tester.pump(const Duration(milliseconds: 80));
      final sliding = state.verticalOffset;
      await tester.tapAt(cellAt(tester, state, 5, 1) - Offset(0, sliding % kGridRowHeight));
      await tester.pump(const Duration(milliseconds: 16));
      final stopped = state.verticalOffset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.verticalOffset, stopped);
      expect(state.pick, isNull);
    });

    testWidgets('the bar opens the first cell of a picked row where the grid already is', (tester) async {
      final rows = [for (var r = 0; r < 80; r++) 'r$r,x'].join('\n');
      final state = await open(tester, _b('$rows\n'));
      await tester.drag(find.byKey(const ValueKey<String>('grid-pan')), const Offset(0, -900));
      await settle(tester);
      final offset = state.verticalOffset;
      final row = (offset / kGridRowHeight).ceil() + 2;
      await tester.tap(find.byKey(ValueKey<String>('row-$row')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('grid-field')));
      await settle(tester);
      expect(reference(tester), 'A${row + 1}');
      expect(state.editing, isTrue);
      expect(state.verticalOffset, offset);
    });

    testWidgets('undo and redo pick the cell they change and bring it into sight', (tester) async {
      final rows = [for (var r = 0; r < 80; r++) 'r$r,x'].join('\n');
      final state = await open(tester, _b('$rows\n'));
      state.select(const CellPick(40, 1), edit: true);
      await settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'CHANGED');
      await tester.tap(find.bySemanticsLabel('Keep'));
      await settle(tester);
      await tester.drag(find.byKey(const ValueKey<String>('grid-pan')), const Offset(0, 3000));
      await settle(tester);
      expect(state.verticalOffset, 0);
      await tester.tap(find.bySemanticsLabel('Undo'));
      await settle(tester);
      expect(state.pick, const CellPick(40, 1));
      expect(state.verticalOffset, greaterThan(20 * kGridRowHeight));
      expect(state.document.cell(40, 1), 'x');
    });

    testWidgets('dates show in full, and a column is widened by dragging its edge', (tester) async {
      final state = await open(tester, _b('id,Subscribed\n1,2019-04-12\n2,2020-11-30\n'));
      final painter = TextPainter(text: TextSpan(text: '2019-04-12', style: AppText.cell), textDirection: TextDirection.ltr)
        ..layout();
      final column = tester.getSize(find.byKey(const ValueKey<String>('column-1'))).width;
      expect(column, greaterThanOrEqualTo(painter.width + 16));
      painter.dispose();
      await tester.drag(find.byKey(const ValueKey<String>('widen-B')), const Offset(60, 0));
      await settle(tester);
      expect(tester.getSize(find.byKey(const ValueKey<String>('column-1'))).width, greaterThan(column + 30));
      expect(state.document.changed, isFalse);
    });

    testWidgets('undo is there from the first words typed', (tester) async {
      final state = await open(tester, _b('name,city\nAda,Leeds\n'));
      await quickTaps(tester, cellAt(tester, state, 1, 1));
      await tester.enterText(find.byType(EditableText).first, 'Yorkk');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Undo'));
      await settle(tester);
      expect(state.document.cell(1, 1), 'Leeds');
      expect(state.document.changed, isFalse);
    });

    testWidgets('a long press on a cell picks it and offers its actions at once', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n'));
      await tester.longPressAt(cellAt(tester, state, 1, 1));
      await settle(tester);
      expect(reference(tester), 'B2');
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsOneWidget);
    });

    testWidgets('undoing an inserted last row leaves no dead actions up', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n'));
      await tester.tap(find.byKey(const ValueKey<String>('row-1')));
      await settle(tester);
      await tester.tap(find.text('Insert below'));
      await settle(tester);
      expect(state.document.rowCount, 3);
      await tester.tap(find.bySemanticsLabel('Undo'));
      await settle(tester);
      expect(state.document.rowCount, 2);
      expect(find.text('Insert below'), findsNothing);
    });

    testWidgets('the keyboard coming up keeps the cell being typed into in sight', (tester) async {
      final rows = [for (var i = 0; i < 40; i++) 'row $i,x'].join('\n');
      final state = await open(tester, _b('name,v\n$rows\n'));
      await quickTaps(tester, cellAt(tester, state, 16, 0));
      tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final body = tester.getRect(find.byKey(const ValueKey<String>('grid-body')));
      final down = body.top + 16 * kGridRowHeight - state.verticalOffset;
      expect(down, greaterThanOrEqualTo(body.top));
      expect(down + kGridRowHeight, lessThanOrEqualTo(body.bottom + 0.5));
    });

    testWidgets('words typed but not yet kept count, and are kept on moving anywhere', (tester) async {
      final state = await open(tester, _b('name,city\nAda,Leeds\nBo,Hull\n'));
      await quickTaps(tester, cellAt(tester, state, 1, 1));
      await tester.enterText(find.byType(EditableText).first, 'York');
      await tester.pump();
      final save = tester.widget<EditButton>(find.ancestor(of: find.text('SAVE'), matching: find.byType(EditButton)));
      expect(save.enabled, isTrue);
      await tester.tap(find.bySemanticsLabel('Back to the document'));
      await settle(tester);
      expect(find.text('Keep editing'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('row-2')));
      await settle(tester);
      expect(state.document.cell(1, 1), 'York');
    });

    testWidgets('the picked cell shows the words as they are typed', (tester) async {
      final state = await open(tester, _b('name,city\nAda,Leeds\n'));
      await quickTaps(tester, cellAt(tester, state, 1, 1));
      await tester.enterText(find.byType(EditableText).first, 'Yor');
      await tester.pump();
      final shown = find.descendant(of: find.byKey(const ValueKey<String>('grid-body')), matching: find.text('Yor'));
      expect(shown, findsOneWidget);
      expect(state.document.cell(1, 1), 'Leeds');
    });

    testWidgets('undo while typing takes back the typing, and redo brings it back', (tester) async {
      final state = await open(tester, _b('a,b\n1,2\n3,4\n'));
      await quickTaps(tester, cellAt(tester, state, 1, 0));
      await tester.enterText(find.byType(EditableText).first, 'first');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'second');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Undo'));
      await settle(tester);
      expect(state.document.cell(1, 0), 'first');
      expect(state.document.cell(2, 0), '3');
      await tester.tap(find.bySemanticsLabel('Redo'));
      await settle(tester);
      expect(state.document.cell(2, 0), 'second');
    });

    testWidgets('a row or column past the data offers nothing that would do nothing', (tester) async {
      await open(tester, _b('a,b\n1,2\n'));
      await tester.tap(find.byKey(const ValueKey<String>('row-5')));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('column-3')));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('row-1')));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsOneWidget);
    });

    testWidgets('one diagonal drag moves the grid across and down together', (tester) async {
      final header = [for (var c = 0; c < 30; c++) 'column $c'].join(',');
      final rows = [for (var r = 0; r < 100; r++) [for (var c = 0; c < 30; c++) '$r.$c'].join(',')].join('\n');
      final state = await open(tester, _b('$header\n$rows\n'));
      await tester.timedDragFrom(
        cellAt(tester, state, 8, 2),
        const Offset(-200, -200),
        const Duration(milliseconds: 600),
      );
      await settle(tester);
      expect(state.horizontalOffset, greaterThan(150));
      expect(state.verticalOffset, greaterThan(150));
    });

    testWidgets('a cell\'s bar of actions goes when the grid moves', (tester) async {
      final rows = [for (var r = 0; r < 100; r++) '$r,x'].join('\n');
      final state = await open(tester, _b('n,v\n$rows\n'));
      await tester.tapAt(cellAt(tester, state, 3, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(cellAt(tester, state, 3, 0));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsOneWidget);
      await tester.drag(find.byKey(const ValueKey<String>('grid-body')), const Offset(0, -300));
      await settle(tester);
      expect(find.byKey(const ValueKey<String>('grid-actions')), findsNothing);
    });

    testWidgets('columns keep their widths whatever is typed into them', (tester) async {
      final state = await open(tester, _b('id,name,qty\n1,Ada,3\n2,Bo,4\n3,Cy,5\n'));
      final before = tester.getRect(find.byKey(const ValueKey<String>('column-2')));
      await quickTaps(tester, cellAt(tester, state, 1, 0));
      await tester.enterText(find.byType(EditableText).first, 'ID-2026-000001-NORTH-WAREHOUSE');
      await tester.tap(find.bySemanticsLabel('Keep'));
      await settle(tester);
      expect(state.document.cell(1, 0), 'ID-2026-000001-NORTH-WAREHOUSE');
      expect(tester.getRect(find.byKey(const ValueKey<String>('column-2'))), before);
    });

    testWidgets('the sample opens and nothing is saved until something changes', (tester) async {
      final bytes = (await tester.runAsync(() => documentBytes(kSubscribers)))!;
      await open(tester, bytes);
      expect(find.text('SAVE'), findsOneWidget);
      await tester.tap(find.text('SAVE'));
      await settle(tester);
      expect(saved, isNull);
    });
  });
}
