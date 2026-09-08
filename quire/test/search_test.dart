import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/model/search.dart';

import 'support/fixtures.dart';

/// A document shaped the way a PDF's text layer arrives: one section per page,
/// each holding its merged runs as paragraphs.
///
/// The page engine builds the real one, but the shape is fixed by the model,
/// so the prose strategy can be proven against it here without waiting for it.
QuireDocument pdfTextLayer() => const QuireDocument(
      title: 'Press Lease',
      sourceFormat: 'pdf',
      sections: <DocSection>[
        DocSection(
          'Page 1',
          <DocBlock>[
            ParagraphBlock(<DocSpan>[
              DocSpan('This lease of one press and its furniture')
            ]),
            ParagraphBlock(<DocSpan>[
              DocSpan('is made between the parties named below.')
            ]),
          ],
          kind: 'page',
        ),
        DocSection(
          'Page 2',
          <DocBlock>[
            ParagraphBlock(<DocSpan>[
              DocSpan('The press shall be returned in working order.')
            ]),
          ],
          kind: 'page',
        ),
      ],
    );

void main() {
  group('the right strategy for the shape of the document', () {
    test('prose sources index, grid sources do not', () async {
      expect(searchFor(await parsedDocument(kHouseStyle)), isA<ProseSearch>());
      expect(searchFor(await parsedDocument(kBinderyNotes)), isA<ProseSearch>());
      expect(searchFor(pdfTextLayer()), isA<ProseSearch>());

      expect(searchFor(await parsedDocument(kSubscribers)), isA<GridSearch>());
      expect(
          searchFor(await parsedDocument(kPressRunCosts)), isA<GridSearch>());
    });

    test('a Word table does not turn a document into a grid', () async {
      final doc = await parsedDocument(kHouseStyle);
      final tables = <TableBlock>[
        for (final b in doc.sections.single.blocks)
          if (b is TableBlock) b,
      ];
      expect(tables.single.grid, isFalse);
      expect(searchFor(doc), isA<ProseSearch>());
    });

    test('the grid strategy builds no index at all', () async {
      final grid =
          searchFor(await parsedDocument(kSubscribers)) as GridSearch;
      expect(grid.document.sections.single.blocks.single, isA<TableBlock>());
      // Nothing to assert about an index because there is none: the only
      // state a GridSearch keeps is a row offset per section.
      expect(grid.unitCount, 71);
    });
  });

  group('one query across every format', () {
    test('press is found in all five, and the counts are the real ones',
        () async {
      final results = <String, int>{
        'docx': searchFor(await parsedDocument(kHouseStyle))
            .search('press')
            .length,
        'xlsx': searchFor(await parsedDocument(kPressRunCosts))
            .search('press')
            .length,
        'csv': searchFor(await parsedDocument(kSubscribers))
            .search('press')
            .length,
        'md': searchFor(await parsedDocument(kBinderyNotes))
            .search('press')
            .length,
        'pdf': searchFor(pdfTextLayer()).search('press').length,
      };
      expect(results, <String, int>{
        'docx': 6,
        'xlsx': 7,
        'csv': 1,
        'md': 10,
        'pdf': 2,
      });
    });

    test('search is case insensitive in both directions', () async {
      final md = searchFor(await parsedDocument(kBinderyNotes));
      expect(md.search('grain').length, 11);
      expect(md.search('GRAIN').length, 11);
      expect(md.search('Grain').length, 11);
    });

    test('an empty query finds nothing rather than everything', () async {
      expect(searchFor(await parsedDocument(kBinderyNotes)).search(''),
          isEmpty);
      expect(searchFor(await parsedDocument(kSubscribers)).search(''), isEmpty);
    });

    test('a query nothing matches comes back empty', () async {
      expect(
          searchFor(await parsedDocument(kBinderyNotes)).search('vellum'),
          isEmpty);
    });
  });

  group('a hit says exactly where it is', () {
    test('a prose hit carries the block it is in and its offsets', () async {
      final md = searchFor(await parsedDocument(kBinderyNotes));
      final hits = md.search('grain');

      final first = hits.first;
      expect(first.sectionIndex, 0);
      expect(first.blockPath.length, 1, reason: 'a prose block path is flat');
      expect(first.end - first.start, 5);
      expect(first.snippet.toLowerCase(), contains('grain'));
      expect(first.label, 'Bindery Notes');

      final doc = await parsedDocument(kBinderyNotes);
      final block = doc.sections.first.blocks[first.blockPath.single];
      final text = switch (block) {
        HeadingBlock() => block.text,
        ParagraphBlock() => block.text,
        ListItemBlock() => block.text,
        CodeBlock() => block.text,
        _ => '',
      };
      expect(text.substring(first.start, first.end).toLowerCase(), 'grain');
    });

    test('a grid hit carries block, row, column and sub block', () async {
      final csv = searchFor(await parsedDocument(kSubscribers));
      final hits = csv.search('Folio');
      expect(hits.length, 16);

      final first = hits.first;
      expect(first.blockPath.length, 4);
      expect(first.blockPath.first, 0, reason: 'the one grid block');
      expect(first.blockPath[2], 4, reason: 'Folio lives in the Tier column');
      expect(first.label, 'Subscribers');

      final doc = await parsedDocument(kSubscribers);
      final grid = doc.sections.first.blocks.first as TableBlock;
      final cell = grid.rows[first.blockPath[1]].cells[first.blockPath[2]];
      expect(cell.text.substring(first.start, first.end), 'Folio');
    });

    test('a workbook hit names the sheet it was found on', () async {
      final xlsx = searchFor(await parsedDocument(kPressRunCosts));
      final labels = xlsx.search('press').map((h) => h.label).toSet();
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(<String>['Runs', 'Paper', 'Summary'], contains(label));
      }
    });

    test('two matches in one block are two hits, not one', () {
      const doc = QuireDocument(
        title: 'x',
        sections: <DocSection>[
          DocSection('x', <DocBlock>[
            ParagraphBlock(<DocSpan>[DocSpan('press and press and press')]),
          ]),
        ],
      );
      final hits = ProseSearch(doc).search('press');
      expect(hits.length, 3);
      expect(hits.map((h) => h.start).toList(), <int>[0, 10, 20]);
    });

    test('a merged cell is searched once, through its anchor only', () {
      final doc = QuireDocument(
        title: 'x',
        sections: <DocSection>[
          DocSection('x', <DocBlock>[
            TableBlock(<DocRow>[
              DocRow(<DocCell>[
                const DocCell(<DocBlock>[
                  ParagraphBlock(<DocSpan>[DocSpan('press')])
                ], colSpan: 2),
                const DocCell(<DocBlock>[
                  ParagraphBlock(<DocSpan>[DocSpan('press')])
                ], merged: true),
              ]),
            ], grid: true),
          ]),
        ],
      );
      expect(GridSearch(doc).search('press').length, 1);
    });
  });

  group('the fore edge scale', () {
    test('prose counts blocks, a grid counts rows', () async {
      expect(searchFor(await parsedDocument(kBinderyNotes)).unitCount, 70);
      expect(searchFor(await parsedDocument(kHouseStyle)).unitCount, 65);
      expect(searchFor(await parsedDocument(kSubscribers)).unitCount, 71);
      expect(searchFor(await parsedDocument(kPressRunCosts)).unitCount, 56,
          reason: '26 plus 14 plus 16 rows over three sheets');
    });

    test('positions run from 0 to 1 and never go backwards', () async {
      final md = searchFor(await parsedDocument(kBinderyNotes));
      final positions =
          md.search('press').map(md.positionOf).toList();

      expect(positions.first, greaterThanOrEqualTo(0.0));
      expect(positions.last, lessThanOrEqualTo(1.0));
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], greaterThanOrEqualTo(positions[i - 1]),
            reason: 'hits come back in document order');
      }
    });

    test('a grid position follows the row, across sheets', () async {
      final xlsx =
          searchFor(await parsedDocument(kPressRunCosts)) as GridSearch;
      final hits = xlsx.search('press');
      expect(hits, isNotEmpty);

      for (final hit in hits) {
        final position = xlsx.positionOf(hit);
        expect(position, inInclusiveRange(0.0, 1.0));
      }

      // The same row on a later sheet must sit further down the whole
      // document than it does on the first sheet.
      const early = DocHit(0, <int>[0, 5, 0, 0], 0, 5, '', 'Runs');
      const later = DocHit(2, <int>[0, 5, 0, 0], 0, 5, '', 'Summary');
      expect(xlsx.positionOf(later), greaterThan(xlsx.positionOf(early)));
    });

    test('a one block document reports position 0 rather than dividing by 0',
        () {
      const doc = QuireDocument(
        title: 'x',
        sections: <DocSection>[
          DocSection('x', <DocBlock>[
            ParagraphBlock(<DocSpan>[DocSpan('press')]),
          ]),
        ],
      );
      final search = ProseSearch(doc);
      expect(search.positionOf(search.search('press').single), 0.0);
    });

    test('a hit from another document does not crash positionOf', () async {
      final md = searchFor(await parsedDocument(kBinderyNotes));
      const stranger = DocHit(9, <int>[999], 0, 1, '', 'nowhere');
      expect(md.positionOf(stranger), 0.0);
    });
  });

  group('snippets', () {
    test('a snippet is a window, not the whole block', () {
      final long = 'a' * 200;
      final text = '${long}press$long';
      expect(snippetAround(text, 200, 5).length, 5 + 48);
      expect(snippetAround(text, 200, 5), contains('press'));
    });

    test('a snippet at the very start does not run off the front', () {
      expect(snippetAround('press run', 0, 5), 'press run');
    });
  });
}
