import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/formula_shift.dart';
import 'package:quire/format/number_format.dart';
import 'package:quire/format/xlsx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/sheet_geometry.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart'
    show cellAt, commentsOn;
import 'package:quire/theme/metrics.dart';

const _main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// A workbook the way current Excel writes one, built here so every part of
/// it can be read in a diff: a formula filled down, fills from the theme and
/// from the old numbered colours, a filled cell with nothing in it, a
/// conversation with a reply and a note on an empty cell, a hidden row and
/// column and sheet, and a sheet's own plain column and row.
Uint8List _workbook() {
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
<workbook xmlns="$_main" xmlns:r="$_rel">
  <sheets>
    <sheet name="Runs" sheetId="1" r:id="rId1"/>
    <sheet name="Workings" sheetId="2" state="hidden" r:id="rId2"/>
  </sheets>
</workbook>''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$_pkg">
  <Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="$_rel/worksheet"/>
  <Relationship Id="rId2" Target="worksheets/sheet2.xml" Type="$_rel/worksheet"/>
  <Relationship Id="rId3" Target="styles.xml" Type="$_rel/styles"/>
  <Relationship Id="rId4" Target="theme/theme1.xml" Type="$_rel/theme"/>
  <Relationship Id="rId5" Target="persons/person.xml"
    Type="http://schemas.microsoft.com/office/2017/10/relationships/person"/>
</Relationships>''');
  add('xl/theme/theme1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
      <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="44546A"/></a:dk2>
      <a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>
      <a:accent1><a:srgbClr val="4472C4"/></a:accent1>
      <a:accent2><a:srgbClr val="ED7D31"/></a:accent2>
      <a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>
      <a:accent4><a:srgbClr val="FFC000"/></a:accent4>
      <a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>
      <a:accent6><a:srgbClr val="70AD47"/></a:accent6>
      <a:hlink><a:srgbClr val="0563C1"/></a:hlink>
      <a:folHlink><a:srgbClr val="954F72"/></a:folHlink>
    </a:clrScheme>
  </a:themeElements>
</a:theme>''');
  add('xl/styles.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="$_main">
  <fonts count="1"><font><sz val="11"/></font></fonts>
  <fills count="5">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid">
      <fgColor theme="4" tint="0.79998168889431442"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor indexed="13"/></patternFill></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFE08A"/></patternFill></fill>
  </fills>
  <cellXfs count="4">
    <xf numFmtId="0" fontId="0" fillId="0"/>
    <xf numFmtId="0" fontId="0" fillId="2"/>
    <xf numFmtId="0" fontId="0" fillId="3"/>
    <xf numFmtId="0" fontId="0" fillId="4"/>
  </cellXfs>
</styleSheet>''');
  add('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_main">
  <sheetFormatPr baseColWidth="10" defaultRowHeight="16"/>
  <cols><col min="4" max="4" width="12" hidden="1" customWidth="1"/></cols>
  <sheetData>
    <row r="1" ht="28" customHeight="1">
      <c r="A1" s="1" t="inlineStr"><is><t>Themed</t></is></c>
      <c r="B1" s="2" t="inlineStr"><is><t>Indexed</t></is></c>
      <c r="C1" s="3"/>
    </row>
    <row r="2">
      <c r="A2"><v>2</v></c><c r="B2"><v>5</v></c>
      <c r="C2"><f t="shared" ref="C2:C4" si="0">A2*B2</f><v>10</v></c>
    </row>
    <row r="3">
      <c r="A3"><v>3</v></c><c r="B3"><v>5</v></c>
      <c r="C3"><f t="shared" si="0"/><v>15</v></c>
    </row>
    <row r="4" hidden="1">
      <c r="A4"><v>4</v></c><c r="B4"><v>5</v></c>
      <c r="C4"><f t="shared" si="0"/><v>20</v></c>
    </row>
  </sheetData>
</worksheet>''');
  add('xl/worksheets/_rels/sheet1.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="$_pkg">
  <Relationship Id="rId1" Target="../comments1.xml" Type="$_rel/comments"/>
  <Relationship Id="rId2" Target="../threadedComments/threadedComment1.xml"
    Type="http://schemas.microsoft.com/office/2017/10/relationships/threadedComment"/>
</Relationships>''');
  add('xl/comments1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<comments xmlns="$_main">
  <authors>
    <author>tc={2A0C1E5B-7C1D-4F7E-9C1A-6A2B3C4D5E6F}</author>
    <author>Bindery</author>
  </authors>
  <commentList>
    <comment ref="B2" authorId="0"><text><t>[Threaded comment]

Your version of Excel allows you to read this threaded comment; however, any edits to it will get removed if the file is opened in a newer version of Excel.

Comment:
    Is five the right multiplier?</t></text></comment>
    <comment ref="F9" authorId="1"><text><t>Bindery: Leave this row for the spring run.</t></text></comment>
  </commentList>
</comments>''');
  add('xl/threadedComments/threadedComment1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<ThreadedComments xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments">
  <threadedComment ref="B2" dT="2026-03-02T10:00:00.00"
    personId="{P-ADA}" id="{T-1}">
    <text>Is five the right multiplier?</text>
  </threadedComment>
  <threadedComment ref="B2" dT="2026-03-02T11:00:00.00"
    personId="{P-TOM}" id="{T-2}" parentId="{T-1}">
    <text>Yes, for the case bound run.</text>
  </threadedComment>
</ThreadedComments>''');
  add('xl/persons/person.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<personList xmlns="http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments">
  <person displayName="Ada Bindery" id="{P-ADA}" userId="ada" providerId="None"/>
  <person displayName="Tomas Reed" id="{P-TOM}" userId="tom" providerId="None"/>
</personList>''');
  add('xl/worksheets/sheet2.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="$_main"><sheetData>
  <row r="1"><c r="A1" t="inlineStr"><is><t>scratch</t></is></c></row>
</sheetData></worksheet>''');
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

TableBlock _runs() {
  final document = xlsxToDocument(XlsxParser(_workbook()).parse(), 'Runs');
  return document.sections.single.blocks.whereType<TableBlock>().single;
}

void main() {
  group('a formula filled down', () {
    test('moves what is not anchored, and leaves what is', () {
      expect(shiftFormula('A2*B2', 1, 0), 'A3*B3');
      expr() => shiftFormula(r'$A$1+A1+B$1+$C2', 2, 3);
      expect(expr(), r'$A$1+D3+E$1+$C4');
      expect(shiftFormula('SUM(A1:B2)', 3, 1), 'SUM(B4:C5)');
    });

    test('leaves function names, text and sheet names alone', () {
      expect(
        shiftFormula('LOG10(A1)+ATAN2(B1,C1)', 1, 0),
        'LOG10(A2)+ATAN2(B2,C2)',
      );
      expect(shiftFormula('"A1 is "&A1', 1, 1), '"A1 is "&B2');
      expect(shiftFormula("'Q1 A1'!A1*2", 1, 0), "'Q1 A1'!A2*2");
    });

    test('moved off the sheet it cannot be anywhere', () {
      expect(shiftFormula('A1', -1, 0), '#REF!');
    });

    test('each cell of the range reads its own formula', () {
      final table = _runs();
      expect(cellAt(table, 1, 2)!.formula, 'A2*B2');
      expect(cellAt(table, 2, 2)!.formula, 'A3*B3');
      expect(cellAt(table, 3, 2)!.formula, 'A4*B4');
    });
  });

  group('the colours a file names', () {
    test('a theme colour with a tint, and an old numbered one', () {
      final table = _runs();
      // Accent 1, lightened four fifths of the way to white.
      expect(cellAt(table, 0, 0)!.background, 0xFFDAE3F3);
      // Number 13 of the old sixty four is yellow.
      expect(cellAt(table, 0, 1)!.background, 0xFFFFFF00);
    });

    test('a filled cell with nothing in it keeps its fill', () {
      final table = _runs();
      expect(cellAt(table, 0, 2)!.background, 0xFFFFE08A);
      expect(cellAt(table, 0, 2)!.text, isEmpty);
    });

    test('tints lighten and darken in lightness', () {
      expect(tinted(0xFF4472C4, 0), 0xFF4472C4);
      expect(tinted(0xFF000000, 0.5), 0xFF808080);
      expect(tinted(0xFFFFFFFF, -0.5), 0xFF808080);
    });
  });

  group('what people said', () {
    test('a conversation is read with its people, not their ids', () {
      final said = commentsOn(_runs());
      final thread = said.entries
          .firstWhere((entry) => entry.key.row == 1 && entry.key.column == 1)
          .value;
      expect(thread.author, 'Ada Bindery');
      expect(thread.text, startsWith('Is five the right multiplier?'));
      expect(thread.text, contains('Tomas Reed: Yes, for the case bound run.'));
      expect(thread.text, isNot(contains('Threaded comment')));
    });

    test('a note on an empty cell is still a note', () {
      final table = _runs();
      final note = cellAt(table, 8, 5);
      expect(note, isNotNull);
      expect(note!.comment, 'Leave this row for the spring run.');
      expect(note.commentBy, 'Bindery');
    });
  });

  group('what a file hides and measures', () {
    test('a hidden sheet is not one of the sheets shown', () {
      final workbook = XlsxParser(_workbook()).parse();
      expect(workbook.sheets.map((sheet) => sheet.name), <String>['Runs']);
    });

    test('hidden rows and columns take no room', () {
      final geometry = SheetGeometry.of(_runs());
      expect(geometry.heightOf(3), 0);
      expect(geometry.widthOf(3), 0);
    });

    test('heights and widths keep their proportion to a plain one', () {
      final table = _runs();
      final geometry = SheetGeometry.of(table);
      // A 28 point row against the sheet's own plain row of 16 points.
      expect(
        geometry.heightOf(0) / geometry.heightOf(1),
        closeTo(28 / 16, 0.01),
      );
      // A plain column on a sheet whose base width is ten characters is
      // wider than a plain column on a sheet that says nothing.
      expect(geometry.widthOf(0), greaterThan(kGridColumnWidth));
    });
  });

  group('numbers as a spreadsheet shows them', () {
    test('General leaves out the noise a double carries', () {
      expect(formatCell(0.30000000000000004, 'General'), '0.3');
      expect(formatCell(3.3000000000000003, 'General'), '3.3');
      expect(formatCell(1234.5678, 'General'), '1234.5678');
      expect(formatCell(42, 'General'), '42');
      expect(formatCell(123456789012345.0, 'General'), '1.23457E+14');
      expect(formatCell(0.0000000001234, 'General'), '1.234E-10');
    });

    test('a locale currency keeps its symbol', () {
      expect(formatCell(1234.5, r'[$€-407]#,##0.00'), '€1,234.50');
      expect(formatCell(1234.5, r'[$£-809]#,##0.00'), '£1,234.50');
    });

    test('scientific formats', () {
      expect(formatCell(12345.678, '0.00E+00'), '1.23E+04');
      expect(formatCell(0.000123, '0.00E+00'), '1.23E-04');
      expect(formatCell(-12345.678, '0.00E+00'), '-1.23E+04');
      expect(formatCell(12345.678, '##0.0E+0'), '12.3E+3');
      expect(formatCell(0, '0.00E+00'), '0.00E+00');
    });
  });
}
