import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/xlsx_parser.dart';

/// What a workbook does when it asks for more than a phone has.
///
/// None of these files is large. Every one of them is about a kilobyte, and
/// two of them used to take the app away for good: not with an exception, which
/// something could have caught, but by simply never coming back.
void main() {
  group('a sheet that says it is enormous', () {
    test('one cell at the last legal address is refused, not attempted', () {
      // XFD1048576 is the furthest corner the format has. A single cell there
      // asks for a grid of seventeen billion slots.
      final watch = Stopwatch()..start();
      expect(
        () => XlsxParser(bookWithCells('<c r="XFD1048576"><v>1</v></c>')).parse(),
        throwsFormatException,
      );
      watch.stop();
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'it must refuse quickly, not refuse eventually',
      );
    });

    test('a merge over the whole sheet does not expand cell by cell', () {
      final watch = Stopwatch()..start();
      final wb = XlsxParser(
        bookWithCells(
          '<c r="A1"><v>1</v></c>',
          merges: '<mergeCells><mergeCell ref="A1:XFD1048576"/></mergeCells>',
        ),
      ).parse();
      final doc = xlsxToDocument(wb, 'merged');
      watch.stop();

      expect(doc.sections.length, 1);
      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'a merge past the sheet draws nothing and must cost nothing',
      );
    });

    test('a note out past the format cannot stretch the grid', () {
      final wb = XlsxParser(bookWithCells('<c r="A1"><v>1</v></c>')).parse();
      wb.sheets.first.notes['XFD1048576'] = const SheetNote('A', 'far away');

      final watch = Stopwatch()..start();
      final doc = xlsxToDocument(wb, 'noted');
      watch.stop();

      expect(doc.sections.length, 1);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('a reference the format cannot express', () {
    test('column letters past the last column do not wrap to negative', () {
      final (_, col) = XlsxParser.refToRowCol('ZZZZZZZZZZZZZZZ1');
      expect(col, greaterThan(0), reason: 'it overflowed a 64 bit int');
    });

    test('a cell at row zero is dropped, not indexed at minus one', () {
      // A row element with no r attribute and a cell claiming row zero. The
      // grid used to be handed an index of -1.
      final wb = XlsxParser(
        bookWithRows('<row><c r="A0"><v>1</v></c></row>'),
      ).parse();
      expect(wb.sheets.first.grid, isNotEmpty);
    });

    test('a column past the last column is dropped', () {
      final wb = XlsxParser(
        bookWithCells('<c r="A1"><v>1</v></c>'
            '<c r="ZZZZZZZZZZZZZZZ1"><v>2</v></c>'),
      ).parse();
      expect(wb.sheets.first.maxCol, 0);
    });
  });

  group('an ordinary sheet is untouched', () {
    test('it still reads every cell it has', () {
      final wb = XlsxParser(
        bookWithRows(
          '<row r="1"><c r="A1" t="str"><v>Stock</v></c>'
          '<c r="B1" t="str"><v>Sheets</v></c></row>'
          '<row r="2"><c r="A2" t="str"><v>Laid</v></c>'
          '<c r="B2"><v>500</v></c></row>',
        ),
      ).parse();

      final sheet = wb.sheets.single;
      expect(sheet.grid.length, 2);
      expect(sheet.maxCol, 1);
      expect(sheet.grid[0][0]?.formatted, 'Stock');
      expect(sheet.grid[1][1]?.formatted, '500');

      final doc = xlsxToDocument(wb, 'ordinary');
      expect(doc.sections.single.blocks, isNotEmpty);
    });
  });
}

/// A one sheet workbook whose single row holds [cells].
Uint8List bookWithCells(String cells, {String merges = ''}) =>
    bookWithRows('<row r="1">$cells</row>', merges: merges);

/// A one sheet workbook whose sheetData is [rows].
Uint8List bookWithRows(String rows, {String merges = ''}) {
  final sheet =
      '<?xml version="1.0"?>'
      '<worksheet '
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>$rows</sheetData>$merges</worksheet>';
  const workbook =
      '<?xml version="1.0"?>'
      '<workbook '
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships">'
      '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';
  const rels =
      '<?xml version="1.0"?>'
      '<Relationships '
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/></Relationships>';

  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('xl/workbook.xml', workbook);
  add('xl/_rels/workbook.xml.rels', rels);
  add('xl/worksheets/sheet1.xml', sheet);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
