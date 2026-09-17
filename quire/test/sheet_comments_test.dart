import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/xlsx_parser.dart' show XlsxParser, xlsxToDocument;
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart';
import 'package:quire/theme/colors.dart';

import 'support/golden.dart';

/// The smallest workbook that carries a discussion: one sheet, three cells,
/// and two comments on it.
///
/// Built here rather than shipped, because a fixture for this would be a
/// binary nobody can read in a diff, and because building it is what proves
/// the parser is reading the parts a real file actually has.
Uint8List _workbookWithComments() {
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
<Relationships
  xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="xl/workbook.xml"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"/>
</Relationships>''');
  add('xl/workbook.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Runs" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
  add('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships
  xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="worksheets/sheet1.xml"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"/>
</Relationships>''');
  add('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="inlineStr"><is><t>Job</t></is></c>
      <c r="B1" t="inlineStr"><is><t>Client</t></is></c>
    </row>
    <row r="2">
      <c r="A2" t="inlineStr"><is><t>QP-2601</t></is></c>
      <c r="B2" t="inlineStr"><is><t>Thornbury Tea Rooms</t></is></c>
    </row>
  </sheetData>
</worksheet>''');
  add('xl/worksheets/_rels/sheet1.xml.rels', '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships
  xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="../comments1.xml"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"/>
</Relationships>''');
  add('xl/comments1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<comments xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <authors><author>Bindery</author></authors>
  <commentList>
    <comment ref="B2" authorId="0"><text><r>
      <t>Bindery: Check the discount before invoicing.</t>
    </r></text></comment>
    <comment ref="A1" authorId="0"><text><r>
      <t>Numbered by the press, not by us.</t>
    </r></text></comment>
  </commentList>
</comments>''');
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

DocCell _cell(String text, {String? comment, String? by}) => DocCell(
  <DocBlock>[
    ParagraphBlock(<DocSpan>[DocSpan(text)]),
  ],
  comment: comment,
  commentBy: by,
);

void main() {
  group('what a workbook says about its own cells', () {
    test('is read off the part the file keeps it in', () {
      final workbook = XlsxParser(_workbookWithComments()).parse();
      final sheet = workbook.sheets.single;
      expect(sheet.notes.keys.toList()..sort(), <String>['A1', 'B2']);
      expect(sheet.notes['B2']!.author, 'Bindery');
      // The author's name is written into the note as well as beside it, and
      // printing it twice would be the file's habit rather than the reader's.
      expect(sheet.notes['B2']!.text, 'Check the discount before invoicing.');
      expect(sheet.notes['A1']!.text, 'Numbered by the press, not by us.');
    });

    test('reaches the cells themselves', () {
      final document = xlsxToDocument(
        XlsxParser(_workbookWithComments()).parse(),
        'Runs',
      );
      final table =
          document.sections.single.blocks.whereType<TableBlock>().single;
      final said = commentsOn(table);
      expect(said.keys, contains(const SheetCell(1, 1)));
      expect(said[const SheetCell(1, 1)]!.author, 'Bindery');
      expect(said[const SheetCell(0, 0)]!.text, contains('Numbered by'));
      // In reading order, so a list of them reads down the sheet.
      expect(said.keys.first, const SheetCell(0, 0));
    });

    test('a workbook nobody has discussed carries nothing', () {
      final table = TableBlock(
        <DocRow>[
          DocRow(<DocCell>[_cell('a'), _cell('b')]),
        ],
        grid: true,
      );
      expect(commentsOn(table), isEmpty);
    });
  });

  group('a cell that has been discussed', () {
    testWidgets('wears the mark in its corner', (tester) async {
      final table = TableBlock(
        <DocRow>[
          DocRow(<DocCell>[_cell('Job'), _cell('Client')], header: true),
          DocRow(<DocCell>[
            _cell('QP-2601'),
            _cell(
              'Thornbury Tea Rooms',
              comment: 'Check the discount before invoicing.',
              by: 'Bindery',
            ),
          ]),
        ],
        frozenRows: 1,
        grid: true,
      );
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: ColoredBox(
            color: AppColors.ground,
            child: SheetGrid(
              table: table,
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await settle(tester);
      await capture(tester, 'sheet__grid_comment');
    });
  });
}
