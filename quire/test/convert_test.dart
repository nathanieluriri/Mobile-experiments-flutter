import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/csv_parser.dart';
import 'package:quire/format/docx_parser.dart';
import 'package:quire/format/xlsx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/services/convert.dart';
import 'package:quire/services/office_writer.dart';

/// A small document with one of everything the writers claim to carry.
QuireDocument _prose() => QuireDocument(
  title: 'House Style',
  sourceFormat: 'md',
  sections: <DocSection>[
    DocSection('House Style', <DocBlock>[
      const HeadingBlock(1, <DocSpan>[DocSpan('Setting the page')]),
      const ParagraphBlock(<DocSpan>[
        DocSpan('A page is '),
        DocSpan('set', bold: true),
        DocSpan(' before it is '),
        DocSpan('read', italic: true),
        DocSpan('.'),
      ]),
      const ListItemBlock(
        <DocSpan>[DocSpan('Measure first')],
        level: 0,
        ordered: false,
      ),
      const ListItemBlock(
        <DocSpan>[DocSpan('Then cut')],
        level: 0,
        ordered: true,
      ),
      const CodeBlock('one\ntwo', language: 'text'),
    ]),
  ],
);

QuireDocument _grid() => QuireDocument(
  title: 'Press Run Costs',
  sourceFormat: 'xlsx',
  sections: <DocSection>[
    DocSection('Costs', <DocBlock>[
      TableBlock(
        <DocRow>[
          DocRow(
            <DocCell>[
              DocCell(_cell('Stock')),
              DocCell(_cell('Sheets')),
              DocCell(_cell('Note, with a comma')),
            ],
            header: true,
          ),
          DocRow(<DocCell>[
            DocCell(_cell('Laid text')),
            DocCell(_cell('1200')),
            DocCell(_cell('Said "so"')),
          ]),
          DocRow(<DocCell>[
            DocCell(_cell('Wove')),
            DocCell(_cell('980')),
            DocCell(_cell('007')),
          ]),
        ],
        grid: true,
      ),
    ]),
  ],
);

List<DocBlock> _cell(String text) => <DocBlock>[
  ParagraphBlock(<DocSpan>[DocSpan(text)]),
];

void main() {
  group('plain text', () {
    test('keeps the words in reading order and nothing else', () {
      final text = documentAsText(_prose());
      expect(text, contains('Setting the page'));
      expect(text, contains('A page is set before it is read.'));
      expect(text, contains('- Measure first'));
      expect(text, contains('1. Then cut'));
      expect(text, isNot(contains('**')));
    });

    test('a grid comes out tab separated, which a spreadsheet can take', () {
      final text = documentAsText(_grid());
      expect(text, contains('Stock\tSheets\tNote, with a comma'));
    });
  });

  group('markdown', () {
    test('carries the shape, not only the words', () {
      final md = documentAsMarkdown(_prose());
      expect(md, contains('# Setting the page'));
      expect(md, contains('**set**'));
      expect(md, contains('_read_'));
      expect(md, contains('- Measure first'));
      expect(md, contains('```text'));
    });

    test('a table gets a head rule so it renders as a table', () {
      final md = documentAsMarkdown(_grid());
      expect(md, contains('| Stock | Sheets | Note, with a comma |'));
      expect(md, contains('| --- | --- | --- |'));
    });
  });

  group('csv', () {
    test('quotes what RFC 4180 says to quote and nothing else', () {
      final csv = documentAsCsv(_grid());
      final lines = const LineSplitter().convert(csv);
      expect(lines.first, 'Stock,Sheets,"Note, with a comma"');
      expect(lines[1], 'Laid text,1200,"Said ""so"""');
    });

    test('reads back through the app own parser', () {
      final csv = documentAsCsv(_grid());
      final parsed = csvToDocument(readCsv(utf8Bytes(csv)), 'Costs');
      final table = parsed.sections.first.blocks.whereType<TableBlock>().first;
      expect(table.rows.length, 3);
      expect(table.rows[1].cells[2].text, 'Said "so"');
    });
  });

  group('xlsx', () {
    test('a written workbook reads back through the app own parser', () {
      final bytes = writeXlsx(<SheetOut>[
        const SheetOut('Costs', <List<String>>[
          <String>['Stock', 'Sheets', 'Note'],
          <String>['Laid text', '1200', 'Said "so"'],
          <String>['Wove', '980', '007'],
        ]),
      ]);
      final parsed = xlsxToDocument(XlsxParser(bytes).parse(), 'Costs');
      final table = parsed.sections.first.blocks.whereType<TableBlock>().first;
      expect(table.rows.length, 3);
      expect(table.rows.first.cells[0].text, 'Stock');
      expect(table.rows[1].cells[2].text, 'Said "so"');
    });

    test('a leading zero stays text, because it is not arithmetic', () {
      final bytes = writeXlsx(<SheetOut>[
        const SheetOut('Codes', <List<String>>[
          <String>['007', '1200'],
        ]),
      ]);
      final parsed = xlsxToDocument(XlsxParser(bytes).parse(), 'Codes');
      final table = parsed.sections.first.blocks.whereType<TableBlock>().first;
      expect(table.rows.first.cells[0].text, '007');
      expect(table.rows.first.cells[1].text, '1200');
    });

    test('two sheets cannot share a name', () {
      final bytes = writeXlsx(<SheetOut>[
        const SheetOut('Sheet', <List<String>>[]),
        const SheetOut('Sheet', <List<String>>[]),
      ]);
      final parsed = xlsxToDocument(XlsxParser(bytes).parse(), 'Two');
      expect(parsed.sections.length, 2);
      expect(parsed.sections[0].title, isNot(parsed.sections[1].title));
    });
  });

  group('docx', () {
    test('a written file reads back through the app own parser', () {
      final parsed = DocxParser(writeDocx(_prose())).parse(title: 'Style');
      final blocks = parsed.sections.first.blocks;
      expect(
        blocks.whereType<HeadingBlock>().map((b) => b.text),
        contains('Setting the page'),
      );
      final body = blocks.whereType<ParagraphBlock>().map((b) => b.text);
      expect(body, contains('A page is set before it is read.'));
    });

    test('bold and italic survive the trip', () {
      final parsed = DocxParser(writeDocx(_prose())).parse(title: 'Style');
      final spans = parsed.sections.first.blocks
          .whereType<ParagraphBlock>()
          .expand((b) => b.spans);
      expect(spans.any((s) => s.text == 'set' && s.bold), isTrue);
      expect(spans.any((s) => s.text == 'read' && s.italic), isTrue);
    });
  });

  group('what is offered', () {
    test('a document is never offered a conversion into itself', () {
      for (final source in <String>['txt', 'md', 'csv', 'xlsx', 'pdf', 'docx']) {
        final targets = targetsFor(source, hasGrid: true);
        expect(
          targets.map((t) => t.extension),
          isNot(contains(source)),
          reason: source,
        );
      }
    });

    test('a spreadsheet is only offered when there is a grid to make one of',
        () {
      expect(
        targetsFor('pdf', hasGrid: false),
        isNot(contains(ConvertTarget.xlsx)),
      );
      expect(targetsFor('csv', hasGrid: true), contains(ConvertTarget.xlsx));
    });

    test('a grid is never offered as a Word file', () {
      expect(
        targetsFor('xlsx', hasGrid: true),
        isNot(contains(ConvertTarget.docx)),
      );
    });
  });

  group('running one', () {
    test('a spreadsheet becomes a workbook that reads back', () {
      final result = runConvert(
        ConvertSource(title: 'Costs', document: _grid()),
        ConvertTarget.xlsx,
      );
      expect(result, isNotNull);
      final parsed = xlsxToDocument(
        XlsxParser(result!.bytes).parse(),
        'Costs',
      );
      final table = parsed.sections.first.blocks.whereType<TableBlock>().first;
      expect(table.rows.length, 3);
    });

    test('one grid out of two says which one it wrote', () {
      final two = QuireDocument(
        title: 'Two',
        sections: <DocSection>[
          _grid().sections.first,
          DocSection('Second', _grid().sections.first.blocks),
        ],
      );
      final result = runConvert(
        ConvertSource(title: 'Two', document: two),
        ConvertTarget.csv,
      );
      expect(result!.warnings, hasLength(1));
      expect(result.warnings.first.line, contains('Costs'));
    });

    test('a PDF has nothing to make a spreadsheet from', () {
      final result = runConvert(
        const ConvertSource(title: 'Pages'),
        ConvertTarget.csv,
      );
      expect(result, isNull);
    });

    test('a PDF needs the faces it will be set in', () {
      final result = runConvert(
        ConvertSource(title: 'Style', document: _prose()),
        ConvertTarget.pdf,
      );
      expect(result, isNull);
    });

    test('given the faces, it composes a page file that opens', () {
      final result = runConvert(
        ConvertSource(title: 'Style', document: _prose()),
        ConvertTarget.pdf,
        faces: ConvertFaces(
          regular: File('assets/fonts/Inter-Regular.ttf').readAsBytesSync(),
          bold: File('assets/fonts/Inter-Bold.ttf').readAsBytesSync(),
        ),
      );
      expect(result, isNotNull);
      expect(PdfFile.open(result!.bytes).pageCount, greaterThanOrEqualTo(1));
    });
  });

  group('pages', () {
    test('markdown puts a rule where a page ended', () {
      final md = pagesAsMarkdown(<String>['one', 'two']);
      expect(md, contains('---'));
    });

    test('plain text leaves a blank line and no rule', () {
      final text = pagesAsText(<String>['one', 'two']);
      expect(text, 'one\n\ntwo');
    });
  });
}
