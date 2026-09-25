import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/csv_parser.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/format/docx_parser.dart';
import 'package:quire/format/markdown_parser.dart';
import 'package:quire/format/number_format.dart';
import 'package:quire/format/xlsx_parser.dart';
import 'package:quire/model/document.dart';

import 'support/fixtures.dart';

void main() {
  group('csv', () {
    test('subscribers.csv is 71 rows of 6 columns across 73 physical lines',
        () async {
      final bytes = await documentBytes(kSubscribers);
      final table = readCsv(bytes);

      expect(table.encodingNote, 'utf-8 (BOM)');
      expect(table.delimiter, ',');
      expect(table.columnCount, 6);
      expect(table.rows.length, 71, reason: '1 header plus 70 data rows');
      expect(table.raggedRowCount, 0);

      // A line splitting parser would see more rows than there are records,
      // because two records carry a newline inside a quoted field.
      final text = String.fromCharCodes(bytes.sublist(3));
      final physicalLines = RegExp(r'\r\n|\r|\n').allMatches(text).length;
      expect(physicalLines, 73);
      expect(physicalLines - (table.rows.length - 1), 3,
          reason: '2 embedded newlines plus the final terminator');
    });

    test('the header names the six columns', () async {
      final table = readCsv(await documentBytes(kSubscribers));
      expect(table.rows.first,
          <String>['Name', 'Town', 'Country', 'Subscribed', 'Tier', 'Notes']);
    });

    test('quoting survives commas, doubled quotes and embedded newlines',
        () async {
      final table = readCsv(await documentBytes(kSubscribers));

      // A field quoted because it holds the delimiter keeps the comma and
      // loses the quotes.
      expect(table.rows[1][5], 'Prefers the deckle edge, always');

      // A doubled quote collapses to one.
      expect(table.rows[7][5], contains('"paper weather report"'));
      expect(table.rows[7][5], isNot(contains('""')));

      // Two records carry a hard newline inside a quoted field.
      final wrapped =
          table.rows.where((r) => r[5].contains('\n')).toList();
      expect(wrapped.length, 2);
      expect(table.rows[13][5],
          'Two addresses on file:\nsummer at the lake house, winter in town');
      expect(table.rows[26][5],
          'Ship flat, never rolled.\nNo signature required at the door.');
    });

    test('a trailing empty field is a field, not a missing one', () async {
      final table = readCsv(await documentBytes(kSubscribers));
      expect(table.rows[44].length, 6);
      expect(table.rows[44][5], '');
    });

    test('a leading zero stays a string', () async {
      final table = readCsv(await documentBytes(kSubscribers));
      expect(table.rows[52][4], '0412');

      final doc = csvToDocument(table, 'Subscribers');
      final grid = doc.sections.first.blocks.first as TableBlock;
      final cell = grid.rows[52].cells[4];
      expect(cell.numeric, isFalse);
      expect(cell.raw, '0412');
      expect(cell.text, '0412');
    });

    test('the bridged grid freezes one header row and pads every row',
        () async {
      final doc =
          csvToDocument(readCsv(await documentBytes(kSubscribers)), 'Subs');
      expect(doc.sourceFormat, 'csv');
      expect(doc.sections.length, 1);
      expect(doc.sections.first.kind, 'sheet');

      final grid = doc.sections.first.blocks.single as TableBlock;
      expect(grid.grid, isTrue);
      expect(grid.frozenRows, 1);
      expect(grid.rows.length, 71);
      expect(grid.rows.first.header, isTrue);
      for (final row in grid.rows) {
        expect(row.cells.length, 6);
      }
    });

    test('mixed CRLF and LF both end a record', () {
      final rows = parseCsv('a,b\r\nc,d\ne,f');
      expect(rows, <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
        <String>['e', 'f'],
      ]);
    });

    test('a trailing newline does not make a phantom row', () {
      expect(parseCsv('a,b\r\n').length, 1);
      expect(parseCsv('a,b\n\n').length, 2, reason: 'a blank line is a row');
    });

    test('a ragged file reports how ragged it is', () {
      final table = CsvTable(<List<String>>[
        <String>['a', 'b', 'c'],
        <String>['1', '2'],
        <String>['3', '4', '5'],
      ], ',', 'utf-8');
      expect(table.columnCount, 3);
      expect(table.raggedRowCount, 1);
    });

    test('the delimiter is sniffed by consistency, not by frequency', () {
      const text = 'a;b;c\r\n"one, two";three;four\r\n"five, six";seven;eight';
      expect(sniffDelimiter(text), ';');
    });

    test('garbage bytes decode rather than throw', () {
      final garbage =
          Uint8List.fromList(List<int>.generate(500, (i) => (i * 7) % 251));
      final table = readCsv(garbage);
      expect(table.rows, isNotEmpty);
      expect(table.encodingNote, isNotEmpty);
    });

    test('an empty file is empty, not an exception', () {
      final table = readCsv(Uint8List(0));
      expect(table.rows, isEmpty);
      expect(table.columnCount, 0);
    });
  });

  group('xlsx', () {
    test('the workbook has three named sheets in file order', () async {
      final wb = XlsxParser(await documentBytes(kPressRunCosts)).parse();
      expect(wb.sheets.map((s) => s.name).toList(),
          <String>['Runs', 'Paper', 'Summary']);
      expect(wb.date1904, isFalse);
    });

    test('Runs is A1:I26 with a frozen pane, a merged title and custom widths',
        () async {
      final wb = XlsxParser(await documentBytes(kPressRunCosts)).parse();
      final runs = wb.sheets.first;

      expect(runs.grid.length, 26);
      expect(runs.maxCol, 8, reason: 'column I is index 8');
      expect(runs.frozenRows, 2);
      expect(runs.frozenCols, 0);
      expect(runs.merges, <List<int>>[
        <int>[0, 0, 0, 8],
      ]);
      expect(runs.colWidths[0], 13.5);
      expect(runs.colWidths[1], 34.0);
      expect(runs.rowHeights[0], 28.0);
    });

    test('strings come from the shared table, not from inline strings',
        () async {
      final bytes = await documentBytes(kPressRunCosts);
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = zip.files.map((f) => f.name).toList();
      expect(names, contains('xl/sharedStrings.xml'));

      final runs = XlsxParser(bytes).parse().sheets.first;
      final header = runs.cell('A2')!;
      expect(header.kind, CellKind.text);
      expect(header.formatted, isNotEmpty);
      expect(header.raw, isA<String>());
    });

    test('every cached formula value matches what the formula computes',
        () async {
      final wb = XlsxParser(await documentBytes(kPressRunCosts)).parse();
      final runs = wb.sheets[0];
      final paper = wb.sheets[1];

      var checked = 0;
      for (var row = 3; row <= 26; row++) {
        final g = runs.cell('G$row');
        if (g == null) continue;
        expect(g.formula, 'D$row*E$row+F$row');
        final d = (runs.cell('D$row')!.raw! as num).toDouble();
        final e = (runs.cell('E$row')!.raw! as num).toDouble();
        final f = (runs.cell('F$row')!.raw! as num).toDouble();
        expect((g.raw! as num).toDouble(), closeTo(d * e + f, 1e-9),
            reason: 'cached G$row disagrees with D$row*E$row+F$row');
        checked++;
      }
      expect(checked, 24);

      var ratios = 0;
      for (var row = 3; row <= 14; row++) {
        final f = paper.cell('F$row');
        if (f == null) continue;
        expect(f.formula, 'E$row/D$row');
        final d = (paper.cell('D$row')!.raw! as num).toDouble();
        final e = (paper.cell('E$row')!.raw! as num).toDouble();
        expect((f.raw! as num).toDouble(), closeTo(e / d, 1e-9));
        ratios++;
      }
      expect(ratios, 12);
    });

    test('a cross sheet SUM keeps the value the file cached', () async {
      final wb = XlsxParser(await documentBytes(kPressRunCosts)).parse();
      final summary = wb.sheets[2];
      final total = summary.cell('B3')!;
      expect(total.formula, 'SUM(Runs!G3:G26)');

      var sum = 0.0;
      final runs = wb.sheets[0];
      for (var row = 3; row <= 26; row++) {
        final g = runs.cell('G$row');
        if (g?.raw is num) sum += (g!.raw! as num).toDouble();
      }
      expect((total.raw! as num).toDouble(), closeTo(sum, 1e-6));

      final count = summary.cell('B4')!;
      expect(count.formula, 'COUNTA(Runs!A3:A26)');
      expect(count.raw, 24);
    });

    test('a formula cell keeps its cached value and its source together',
        () async {
      final doc = xlsxToDocument(
          XlsxParser(await documentBytes(kPressRunCosts)).parse(), 'Costs');
      final runs = doc.sections.first.blocks.single as TableBlock;
      final g3 = runs.rows[2].cells[6];

      expect(g3.formula, 'D3*E3+F3');
      expect(g3.raw, isA<num>());
      expect(g3.text, isNot(startsWith('=')));
      expect(g3.numeric, isTrue);
    });

    test('a currency format renders as currency, not as a double', () async {
      final wb = XlsxParser(await documentBytes(kPressRunCosts)).parse();
      final runs = wb.sheets.first;
      final money = runs
          .byRef.values
          .where((c) => c.numFmt.contains('#,##0.00'))
          .toList();
      expect(money, isNotEmpty);
      for (final cell in money.take(5)) {
        expect(cell.formatted, isNot(matches(r'^-?\d+(\.\d+)?$')),
            reason: '${cell.ref} rendered as a bare number');
      }
    });

    test('the bridged model is one section per sheet, all grids', () async {
      final doc = xlsxToDocument(
          XlsxParser(await documentBytes(kPressRunCosts)).parse(), 'Costs');
      expect(doc.sourceFormat, 'xlsx');
      expect(doc.sections.length, 3);
      expect(doc.outline.length, 3);
      for (final section in doc.sections) {
        expect(section.kind, 'sheet');
        final grid = section.blocks.single as TableBlock;
        expect(grid.grid, isTrue);
      }
      final runs = doc.sections.first.blocks.single as TableBlock;
      expect(runs.frozenRows, 2);
      expect(runs.rows.first.cells.first.colSpan, 9,
          reason: 'the merged title spans A1:I1');
      expect(runs.rows.first.cells[1].merged, isTrue);
    });

    test('a column reference beyond Z decodes correctly', () {
      expect(XlsxParser.refToRowCol('A1'), (0, 0));
      expect(XlsxParser.refToRowCol('I26'), (25, 8));
      expect(XlsxParser.refToRowCol('BC12'), (11, 54));
      expect(XlsxParser.colName(0), 'A');
      expect(XlsxParser.colName(26), 'AA');
      expect(XlsxParser.colName(54), 'BC');
    });

    test('garbage bytes raise ArchiveException, not a crash', () {
      final garbage =
          Uint8List.fromList(List<int>.generate(500, (i) => (i * 13) % 251));
      expect(() => XlsxParser(garbage).parse(), throwsA(isA<Exception>()));
    });

    test('a docx zip raises FormatException from the xlsx parser', () async {
      final bytes = await documentBytes(kHouseStyle);
      expect(() => XlsxParser(bytes).parse(), throwsFormatException);
    });
  });

  group('number formats', () {
    test('a serial becomes the date the source means', () {
      expect(excelSerialToDate(1), DateTime.utc(1900, 1, 1));
      expect(excelSerialToDate(59), DateTime.utc(1900, 2, 28));
      expect(excelSerialToDate(61), DateTime.utc(1900, 3, 1),
          reason: 'serial 60 is the leap day that never happened');
      expect(excelSerialToDate(45000), DateTime.utc(2023, 3, 15));
      expect(excelSerialToDate(1, date1904: true), DateTime.utc(1904, 1, 2));
    });

    test('date tokens are recognised only outside literals', () {
      expect(isDateFormat('d mmm yyyy'), isTrue);
      expect(isDateFormat('h:mm:ss'), isTrue);
      expect(isDateFormat('General'), isFalse);
      expect(isDateFormat('0.00%'), isFalse);
      expect(isDateFormat(r'"dm"#,##0'), isFalse,
          reason: 'letters inside quotes are text, not tokens');
    });

    test('a format splits into its sections without breaking on a quoted ;',
        () {
      expect(formatSections('#,##0;(#,##0);-;@'),
          <String>['#,##0', '(#,##0)', '-', '@']);
      expect(formatSections(r'"a;b"0'), <String>[r'"a;b"0']);
    });

    test('numbers render the way the sheet says', () {
      expect(formatCell(1234.5, '#,##0.00'), '1,234.50');
      expect(formatCell(0.3125, '0.0%'), '31.3%');
      expect(formatCell(-1234, '#,##0 ;(#,##0)'), '(1,234)');
      expect(formatCell(1234.567, r'"$"#,##0.000'), r'$1,234.567');
      expect(formatCell(0, 'General'), '0');
      expect(formatCell('vellum', '@'), 'vellum');
      expect(formatCell(null, '#,##0'), '');
    });

    test('a date format renders the date, not the serial', () {
      expect(formatCell(45000, 'd mmm yyyy'), '15 Mar 2023');
      expect(formatCell(45000, 'yyyy-mm-dd'), '2023-03-15');
    });
  });

  group('docx', () {
    test('house-style.docx parses to one section of blocks in order',
        () async {
      final doc = DocxParser(await documentBytes(kHouseStyle))
          .parse(title: 'House Style');
      expect(doc.sourceFormat, 'docx');
      expect(doc.sections.length, 1);
      expect(doc.sections.first.kind, 'body');
      final blocks = doc.sections.first.blocks;
      expect(blocks.length, 50);
      expect(blocks.whereType<HeadingBlock>().length, 11);
      expect(blocks.whereType<ParagraphBlock>().length, 24);
      expect(blocks.whereType<ListItemBlock>().length, 13);
      expect(blocks.whereType<ImageBlock>().length, 1);
      expect(blocks.whereType<TableBlock>().length, 1);
    });

    test('style ids resolve to heading levels', () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      final headings =
          doc.sections.first.blocks.whereType<HeadingBlock>().toList();
      expect(headings.length, 11);
      expect(headings.map((h) => h.level).toList(),
          <int>[1, 2, 3, 3, 2, 2, 2, 2, 2, 3, 2]);
      expect(headings.first.text.trim(), isNotEmpty);
      expect(doc.outline.length, headings.length);
      expect(doc.outline.first.title, headings.first.text);
    });

    test('numbering resolves to real markers, not to its own pattern',
        () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      final items =
          doc.sections.first.blocks.whereType<ListItemBlock>().toList();
      expect(items.length, 13);
      expect(items.map((i) => i.marker).toList(), <String>[
        '•', '•', '•', '•',
        '◦', '◦',
        '1.', '2.', '3.', '4.',
        'a)', 'b)',
        '5.',
      ]);
      expect(items.map((i) => i.level).toList(),
          <int>[0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 0]);
      expect(items.map((i) => i.ordered).toList(), <bool>[
        false, false, false, false, false, false,
        true, true, true, true, true, true, true,
      ]);

      // A symbol font's private use bullet must never reach a renderer.
      for (final item in items) {
        final code = item.marker!.codeUnitAt(0);
        expect(code, lessThan(0xE000),
            reason: 'marker "${item.marker}" is still a private use glyph');
      }
    });

    test('run properties survive into spans', () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      final spans = <DocSpan>[
        for (final b in doc.sections.first.blocks)
          if (b is ParagraphBlock) ...b.spans,
      ];
      expect(spans.any((s) => s.bold), isTrue);
      expect(spans.any((s) => s.italic), isTrue);
    });

    test('the table keeps its columns and its rows', () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      final tables =
          doc.sections.first.blocks.whereType<TableBlock>().toList();
      expect(tables.length, 1);
      final table = tables.single;
      expect(table.grid, isFalse, reason: 'a Word table is not a spreadsheet');
      expect(table.rows.length, 6);
      expect(table.columns.map((c) => c.width).toList(),
          <double>[170.0, 130.0, 130.0]);
      expect(table.rows.first.header, isTrue);
      expect(table.frozenRows, 1);
      expect(table.rows.first.cells.map((c) => c.text).toList(),
          <String>['Kind of number', 'How we set it', 'Aligned on']);

      // Word removes the cells a gridSpan swallows, so the last row is one
      // cell three columns wide rather than one cell and two blanks.
      expect(table.rows.take(5).map((r) => r.cells.length).toSet(), <int>{3});
      expect(table.rows.last.cells.length, 1);
      expect(table.rows.last.cells.single.colSpan, 3);

      for (final row in table.rows) {
        for (final cell in row.cells) {
          expect(cell.formula, isNull, reason: 'only a sheet has formulas');
          expect(cell.text.trim(), isNotEmpty);
        }
      }
    });

    test('the embedded picture lands in assets and is referenced by a block',
        () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      expect(doc.assets.keys, contains('word/media/proof-rule.png'));
      expect(doc.assets['word/media/proof-rule.png']!.length, greaterThan(100));

      final images = doc.sections.first.blocks.whereType<ImageBlock>().toList();
      expect(images.length, 1);
      expect(doc.assets.containsKey(images.single.assetKey), isTrue);
    });

    test('a quotation style becomes a quote paragraph', () async {
      final doc = DocxParser(await documentBytes(kHouseStyle)).parse();
      final quotes = doc.sections.first.blocks
          .whereType<ParagraphBlock>()
          .where((p) => p.quote)
          .toList();
      expect(quotes, isNotEmpty);
    });

    test('garbage, a truncated zip and an empty file all throw', () async {
      final garbage =
          Uint8List.fromList(List<int>.generate(500, (i) => (i * 3) % 251));
      final truncated =
          (await documentBytes(kHouseStyle)).sublist(0, 900);

      expect(() => DocxParser(garbage).parse(), throwsA(isA<Exception>()));
      expect(() => DocxParser(truncated).parse(), throwsA(isA<Exception>()));
      expect(() => DocxParser(Uint8List(0)).parse(), throwsA(isA<Exception>()));
    });

    test('an xlsx zip raises FormatException from the docx parser', () async {
      final bytes = await documentBytes(kPressRunCosts);
      expect(() => DocxParser(bytes).parse(), throwsFormatException);
    });
  });

  group('markdown', () {
    String nestedList(int depth) => [
          for (var i = 0; i < depth; i++) '${'  ' * i}- item $i',
        ].join('\n');

    test('a list nested past the limit is refused before it is parsed', () {
      // Used to run for nearly five minutes inside the markdown package.
      final source = nestedList(2000);
      final clock = Stopwatch()..start();
      expect(() => MarkdownParser(source).parse(), throwsFormatException);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('quotes and markers nested on one line count too', () {
      expect(
        () => MarkdownParser('${'> ' * 200}x').parse(),
        throwsFormatException,
      );
      expect(
        () => MarkdownParser('${'- ' * 200}x').parse(),
        throwsFormatException,
      );
      expect(
        () => MarkdownParser(
          [for (var i = 1; i <= 200; i++) '${'>' * i} x'].join('\n'),
        ).parse(),
        throwsFormatException,
      );
    });

    test('a refused file loads as damaged rather than hanging', () {
      final loaded = DocumentLoader.load(
        Uint8List.fromList(utf8.encode(nestedList(2000))),
        'deep.md',
      );
      expect(loaded.failed, isTrue);
      expect(loaded.error, isA<FormatException>());
    });

    test('ordinary nesting and deep indentation still read', () {
      final doc = MarkdownParser(nestedList(20)).parse();
      expect(doc.sections.single.blocks.whereType<ListItemBlock>().length, 20);
      final code = '```\n${' ' * 400}deeply indented code\n```';
      expect(
        MarkdownParser(code).parse().sections.single.blocks.single,
        isA<CodeBlock>(),
      );
    });

    test('nesting is counted from markers, not from any indentation', () {
      expect(MarkdownParser.nestingOf('---'), 0);
      expect(MarkdownParser.nestingOf('*emphasis* here'), 0);
      expect(MarkdownParser.nestingOf('1.5 is a number'), 0);
      expect(MarkdownParser.nestingOf('${' ' * 400}code'), 0);
      expect(MarkdownParser.nestingOf('    - four in'), 3);
      expect(MarkdownParser.nestingOf('> - 1. x'), 3);
    });

    test('bindery-notes.md covers the whole block vocabulary', () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse(title: 'Bindery Notes');

      expect(doc.sourceFormat, 'md');
      final blocks = doc.sections.single.blocks;
      expect(blocks.length, 57);
      expect(blocks.whereType<HeadingBlock>().length, 12);
      expect(blocks.whereType<ParagraphBlock>().length, 20);
      expect(blocks.whereType<ListItemBlock>().length, 20);
      expect(blocks.whereType<CodeBlock>().length, 2);
      expect(blocks.whereType<TableBlock>().length, 1);
      expect(blocks.whereType<DividerBlock>().length, 1);
      expect(blocks.whereType<ImageBlock>().length, 1);
    });

    test('every heading carries a unique anchor and an outline entry',
        () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse();
      final headings = doc.sections.single.blocks.whereType<HeadingBlock>();
      final anchors = headings.map((h) => h.anchor).toList();

      expect(anchors, everyElement(isNotNull));
      expect(anchors.toSet().length, anchors.length,
          reason: 'a repeated heading must not collide');
      expect(anchors.first, 'bindery-notes');
      expect(doc.outline.length, 12);
      expect(doc.outline.first.blockIndex, 0);
    });

    test('an ordered list resumes the source numbering', () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse();
      final markers = doc.sections.single.blocks
          .whereType<ListItemBlock>()
          .where((i) => i.ordered)
          .map((i) => i.marker)
          .toList();
      expect(markers, contains('1.'));
      expect(markers, contains('7.'),
          reason: 'a list that starts at 7 must not restart at 1');
    });

    test('a task list records what is ticked', () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse();
      final tasks = doc.sections.single.blocks
          .whereType<ListItemBlock>()
          .where((i) => i.checked != null)
          .toList();
      expect(tasks.map((t) => t.checked).toList(),
          <bool>[true, true, false, false, false, false]);
    });

    test('a nested blockquote keeps both levels as quote paragraphs',
        () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse();
      final quotes = doc.sections.single.blocks
          .whereType<ParagraphBlock>()
          .where((p) => p.quote)
          .toList();
      expect(quotes.length, greaterThanOrEqualTo(2));
    });

    test('the GFM table keeps its per column alignment', () async {
      final doc = MarkdownParser(
        String.fromCharCodes(await documentBytes(kBinderyNotes)),
      ).parse();
      final table = doc.sections.single.blocks.whereType<TableBlock>().first;
      expect(table.rows.length, 5, reason: 'one header row and four bodies');
      expect(table.rows.first.header, isTrue);
      expect(table.frozenRows, 1);
      expect(table.columns.map((c) => c.align).toList(),
          <DocAlign?>[DocAlign.start, DocAlign.center, DocAlign.end]);
    });

    test('inline emphasis, code and links become span properties', () {
      final doc = MarkdownParser(
        'A **bold** and *slanted* run with `code` and a [link](https://x.dev).',
      ).parse();
      final spans = (doc.sections.single.blocks.single as ParagraphBlock).spans;
      expect(spans.any((s) => s.bold && s.text == 'bold'), isTrue);
      expect(spans.any((s) => s.italic && s.text == 'slanted'), isTrue);
      expect(spans.any((s) => s.mono && s.text == 'code'), isTrue);
      expect(spans.any((s) => s.href == 'https://x.dev'), isTrue);
    });

    test('a fenced block keeps its language and its raw text', () {
      final doc = MarkdownParser('```dart\nvar a = 1;\n```').parse();
      final code = doc.sections.single.blocks.single as CodeBlock;
      expect(code.language, 'dart');
      expect(code.text, 'var a = 1;');
    });

    test('a rule becomes a divider', () {
      final doc = MarkdownParser('one\n\n---\n\ntwo').parse();
      expect(doc.sections.single.blocks.whereType<DividerBlock>().length, 1);
    });

    test('empty source and binary source both parse without throwing', () {
      expect(MarkdownParser('').parse().sections.single.blocks, isEmpty);
      final binary = String.fromCharCodes(
          List<int>.generate(400, (i) => (i * 11) % 251));
      expect(MarkdownParser(binary).parse().sections.single.blocks, isNotEmpty);
    });
  });
}
