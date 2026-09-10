import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/pdf/compose.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/truetype.dart';

Uint8List _font(String weight) =>
    File('assets/fonts/Inter-$weight.ttf').readAsBytesSync();

QuireDocument _document() => QuireDocument(
  title: 'A Working Table of Stocks',
  sourceFormat: 'md',
  sections: <DocSection>[
    DocSection('A Working Table of Stocks', <DocBlock>[
      const HeadingBlock(1, <DocSpan>[DocSpan('Choosing for the run')]),
      const ParagraphBlock(<DocSpan>[
        DocSpan('Start from the ink, not the paper. A solid, an even tint or '
            'a halftone wants a hard, well sized, smooth surface that keeps '
            'the film sitting on top, and anything textured will break the '
            'solid into a field of tiny holidays.'),
      ]),
      const ParagraphBlock(<DocSpan>[
        DocSpan('Then count the '),
        DocSpan('passes', bold: true),
        DocSpan('. Every colour is another trip through the press.'),
      ]),
      const ListItemBlock(
        <DocSpan>[DocSpan('Measure the grain first')],
        level: 0,
        ordered: false,
      ),
      const ListItemBlock(
        <DocSpan>[DocSpan('Then cut')],
        level: 0,
        ordered: false,
      ),
      const DividerBlock(),
      TableBlock(<DocRow>[
        DocRow(
          <DocCell>[
            DocCell(_cell('Stock')),
            DocCell(_cell('Grammage')),
            DocCell(_cell('What we reach for it')),
          ],
          header: true,
        ),
        DocRow(<DocCell>[
          DocCell(_cell('Glassine tissue')),
          DocCell(_cell('45 gsm')),
          DocCell(_cell('Interleaving wet prints')),
        ]),
        DocRow(<DocCell>[
          DocCell(_cell('Binder board, grey')),
          DocCell(_cell('590 gsm')),
          DocCell(_cell('Cased boards, boxes')),
        ]),
      ]),
    ]),
  ],
);

List<DocBlock> _cell(String text) => <DocBlock>[
  ParagraphBlock(<DocSpan>[DocSpan(text)]),
];

/// Every word the reader can pull back off [bytes], page by page.
List<String> _readBack(Uint8List bytes) {
  final file = PdfFile.open(bytes);
  return <String>[
    for (var page = 0; page < file.pageCount; page++)
      mergeRuns(ContentInterpreter(file).run(file.pages[page]).texts)
          .map((run) => run.text)
          .join('\n'),
  ];
}

void main() {
  group('the font', () {
    test('states the glyph and the width for a letter it carries', () {
      final font = TrueTypeFont.parse(_font('Regular'));
      final gid = font.glyphFor('A'.codeUnitAt(0));
      expect(gid, greaterThan(0));
      expect(font.widthOf(gid), greaterThan(300));
      expect(font.measure('AAA', 10), closeTo(font.measure('A', 10) * 3, 0.01));
    });

    test('a letter it does not carry comes out as the empty box', () {
      final font = TrueTypeFont.parse(_font('Regular'));
      // A plane two ideograph, which a Latin face does not have.
      expect(font.glyphFor(0x2A6B2), 0);
      expect(font.covers(0x2A6B2), isFalse);
    });

    test('a subset keeps the glyphs asked for and drops the rest', () {
      final font = TrueTypeFont.parse(_font('Regular'));
      final wanted = <int>{
        for (final rune in 'The quick brown fox'.runes) font.glyphFor(rune),
      };
      final subset = font.subset(wanted);
      expect(subset.length, lessThan(font.bytes.length ~/ 4));
      // It is still a font, and the glyphs kept their numbers.
      final read = TrueTypeFont.parse(subset);
      expect(read.numGlyphs, font.numGlyphs);
      expect(read.unitsPerEm, font.unitsPerEm);
      for (final gid in wanted) {
        expect(read.widthOf(gid), font.widthOf(gid));
      }
    });
  });

  group('a composed page', () {
    late Uint8List bytes;
    late PdfComposer composer;

    setUp(() {
      composer = PdfComposer.of(_font('Regular'), _font('Bold'));
      bytes = composer.compose(_document());
    });

    test('opens through the app own page engine', () {
      final file = PdfFile.open(bytes);
      expect(file.pageCount, greaterThanOrEqualTo(1));
    });

    test('gives its words back to the reader that made it', () {
      final text = _readBack(bytes).join('\n');
      expect(text, contains('Choosing for the run'));
      expect(text, contains('Start from the ink, not the paper.'));
      expect(text, contains('Glassine tissue'));
      expect(text, contains('Binder board, grey'));
    });

    test('breaks lines inside the column rather than running off the page',
        () {
      final file = PdfFile.open(bytes);
      final runs = mergeRuns(
        ContentInterpreter(file).run(file.pages[0]).texts,
      );
      expect(runs, isNotEmpty);
      for (final run in runs) {
        expect(
          run.x + run.width,
          lessThanOrEqualTo(kComposeWidth - kComposeMargin + 1),
          reason: run.text,
        );
        expect(run.x, greaterThanOrEqualTo(kComposeMargin - 1));
      }
    });

    test('carries a folio on every page', () {
      final pages = _readBack(bytes);
      for (var i = 0; i < pages.length; i++) {
        expect(pages[i], contains('${i + 1} of ${pages.length}'));
      }
    });

    test('a long document runs onto more than one page', () {
      final long = QuireDocument(
        title: 'Long',
        sections: <DocSection>[
          DocSection('Long', <DocBlock>[
            for (var i = 0; i < 120; i++)
              ParagraphBlock(<DocSpan>[
                DocSpan('Paragraph $i, which is here to fill the page up so '
                    'that the composer has to start another one.'),
              ]),
          ]),
        ],
      );
      final many = PdfComposer.of(_font('Regular'), _font('Bold'));
      final file = PdfFile.open(many.compose(long));
      expect(file.pageCount, greaterThan(1));
    });

    test('is small, because only the glyphs used are embedded', () {
      // Both faces whole are over eight hundred kilobytes.
      expect(bytes.length, lessThan(120 * 1024));
    });
  });
}
