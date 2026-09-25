import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/services/pdf_structure.dart';

Uint8List _bytes(String name) =>
    File('assets/documents/$name').readAsBytesSync();

void main() {
  group('a page file read back as a document', () {
    late QuireDocument read;

    setUpAll(() {
      read = pdfAsDocument(
        PdfFile.open(_bytes('field-guide-to-paper.pdf')),
        'Field Guide To Paper',
      );
    });

    List<T> all<T extends DocBlock>() => <T>[
      for (final section in read.sections) ...section.blocks.whereType<T>(),
    ];

    test('finds the headings the page sets larger than its body', () {
      final headings = all<HeadingBlock>().map((h) => h.text).toList();
      expect(headings, contains('Reading a Sheet'));
      expect(headings, contains('GRAIN DIRECTION'));
      expect(headings, contains('Weight, and the Two Ways We Measure It'));
    });

    test('joins the lines of a paragraph back into one', () {
      final body = all<ParagraphBlock>().map((p) => p.text).toList();
      // This sentence is broken over three lines on the page.
      expect(
        body.any(
          (p) => p.contains(
            'It arrives at the press carrying a history',
          ) &&
              p.contains('the room where it now waits'),
        ),
        isTrue,
        reason: body.take(6).join(' | '),
      );
    });

    test('reads a two column page down one column and then the other', () {
      // On page two, GRAMMAGE heads the left column and DECKLE EDGES the
      // right. Read down the page instead of down the columns, the paragraph
      // under one lands under the other.
      final text = <String>[
        for (final section in read.sections)
          for (final block in section.blocks)
            switch (block) {
              HeadingBlock() => block.text,
              ParagraphBlock() => block.text,
              _ => '',
            },
      ];
      final basis = text.indexWhere((t) => t.startsWith('BASIS WEIGHT'));
      final deckle = text.indexWhere((t) => t.startsWith('DECKLE EDGES'));
      final sizing = text.indexWhere((t) => t.startsWith('SIZING'));
      expect(basis, greaterThan(-1));
      expect(deckle, greaterThan(-1));
      expect(sizing, greaterThan(-1));
      // The whole of the left column comes before any of the right.
      expect(sizing, lessThan(deckle));
    });

    test('drops the running foot rather than repeating it every page', () {
      final body = all<ParagraphBlock>().map((p) => p.text).toList();
      expect(body.where((p) => p.trim() == 'Quire Press'), isEmpty);
    });

    test('keeps every page it read', () {
      expect(read.sections, hasLength(PdfFile.open(
        _bytes('field-guide-to-paper.pdf'),
      ).pageCount));
    });
  });

  test('a one column page file is left in the order it was set', () {
    final read = pdfAsDocument(
      PdfFile.open(_bytes('press-lease.pdf')),
      'Press Lease',
    );
    expect(read.sections, isNotEmpty);
    final blocks = read.sections.first.blocks;
    expect(blocks, isNotEmpty);
  });
}
