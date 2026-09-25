import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/model/document.dart';

import 'support/fixtures.dart';

/// The one slide block of a section.
SlideBlock _slideOf(QuireDocument deck, int index) =>
    deck.sections[index].blocks.whereType<SlideBlock>().single;

/// Every shape on a slide that holds words.
Iterable<SlideShape> _speaking(SlideBlock slide) =>
    slide.shapes.where((shape) => shape.text.trim().isNotEmpty);

String _allText(SlideBlock slide) =>
    slide.shapes.map((shape) => shape.text).join('\n');

void main() {
  group('the deck parser reads the sample', () {
    late QuireDocument deck;

    setUpAll(() async {
      deck = await parsedDocument(kPressDayBriefing);
    });

    test('one section per slide, in the order the deck presents them', () {
      expect(deck.sourceFormat, 'pptx');
      expect(deck.sections.length, 6);
      expect(deck.sections.every((s) => s.kind == 'slide'), isTrue);
      expect(deck.sections.first.title, 'Press Day Briefing');
      expect(deck.sections[1].title, 'What changes today');
      expect(deck.sections.last.title, 'Sheets off by four, or not at all');
    });

    test('the outline names one entry per slide', () {
      expect(deck.outline.length, 6);
      expect(deck.outline[2].title, 'The run in numbers');
      expect(deck.outline[2].sectionIndex, 2);
      expect(deck.outline.every((e) => e.level == 1), isTrue);
    });

    test('every slide is laid out on the same stage', () {
      for (var i = 0; i < deck.sections.length; i++) {
        final slide = _slideOf(deck, i);
        // Sixteen by nine at 13.333 by 7.5 inches, in points.
        expect(slide.width, closeTo(960, 0.5));
        expect(slide.height, closeTo(540, 0.5));
      }
    });

    test('a title that states no box inherits one from its layout', () {
      // The opening slide owns neither of its two shapes' geometry. A parser
      // that read only the slide would have nowhere to put them.
      final opening = _slideOf(deck, 0);
      final title = opening.shapes.firstWhere(
        (shape) => shape.role == SlideRole.title,
      );
      expect(title.box.left, closeTo(1.2 * 72, 0.5));
      expect(title.box.top, closeTo(2.3 * 72, 0.5));
      expect(title.box.width, closeTo(10.9 * 72, 0.5));
      expect(title.text, 'Press Day Briefing');

      // And the ordinary layout leaves its title to the master, one step
      // further up again.
      final second = _slideOf(deck, 1);
      final heading = second.shapes.firstWhere(
        (shape) => shape.role == SlideRole.title,
      );
      expect(heading.box.left, closeTo(0.9 * 72, 0.5));
      expect(heading.box.top, closeTo(0.5 * 72, 0.5));
    });

    test('a title is a heading, so the outline and the find agree', () {
      final title = _slideOf(deck, 1).shapes.firstWhere(
        (shape) => shape.role == SlideRole.title,
      );
      expect(title.blocks.single, isA<HeadingBlock>());
      expect((title.blocks.single as HeadingBlock).level, 1);
    });

    test('bullets come from the master, at the level the slide asks for', () {
      final body = _slideOf(deck, 1).shapes.firstWhere(
        (shape) => shape.role == SlideRole.body,
      );
      final items = body.blocks.whereType<ListItemBlock>().toList();
      expect(items.length, 5);
      expect(items.first.level, 0);
      expect(items.first.marker, '•');
      expect(items.first.ordered, isFalse);
      // The two indented lines take the second level's own glyph.
      expect(items[2].level, 1);
      expect(items[2].marker, '–');
      expect(items[3].level, 1);
      expect(items.last.level, 0);
    });

    test('a numbered list is numbered from one, in order', () {
      final body = _slideOf(deck, 4).shapes.firstWhere(
        (shape) => shape.role == SlideRole.body,
      );
      final items = body.blocks.whereType<ListItemBlock>().toList();
      expect(items.length, 4);
      expect(items.every((item) => item.ordered), isTrue);
      expect(items.map((item) => item.marker), <String>['1.', '2.', '3.', '4.']);
      expect(items.first.text, 'Lock the forme before you lift it');
    });

    test('run sizes are points, not hundredths of a point', () {
      final title = _slideOf(deck, 0).shapes.firstWhere(
        (shape) => shape.role == SlideRole.title,
      );
      final span = (title.blocks.single as HeadingBlock).spans.single;
      // 5400 in the file, which is 54 point, from the layout's own list style.
      expect(span.fontSize, 54);
      expect(span.bold, isTrue);
    });

    test('scheme colours are resolved through the master colour map', () {
      final subtitle = _slideOf(deck, 0).shapes.firstWhere(
        (shape) => shape.text.startsWith('Michaelmas'),
      );
      final span = (subtitle.blocks.first as ParagraphBlock).spans.single;
      // accent1 in the theme, asked for by name on the layout.
      expect(span.color, 0xFF8A4B2A);

      final heading = _slideOf(deck, 1).shapes.firstWhere(
        (shape) => shape.role == SlideRole.title,
      );
      // tx1 maps to the theme's dk1, not to a literal black.
      expect((heading.blocks.single as HeadingBlock).spans.single.color,
          0xFF1A1A1A);
    });

    test('a colour modifier is applied, not dropped', () {
      // The last slide sets its own ground to accent1 at three quarters
      // luminance. Dropping the modifier would paint it the flat accent.
      final closing = _slideOf(deck, 5);
      expect(closing.background, isNot(0xFF8A4B2A));
      expect(closing.background, 0xFF683820);
    });

    test('a slide with no ground of its own takes the master one', () {
      // lt2 in the theme, mapped to bg2 by the master.
      expect(_slideOf(deck, 1).background, 0xFFF4EFE6);
    });

    test('what the layout and master draw appears on every slide', () {
      // The head rule and the running foot belong to the master. A deck that
      // lost them would be missing the line under every title.
      for (var i = 0; i < deck.sections.length; i++) {
        final slide = _slideOf(deck, i);
        expect(
          slide.shapes.any((shape) => shape.text.contains('michaelmas run')),
          isTrue,
          reason: 'slide ${i + 1} lost the running foot',
        );
        expect(
          slide.shapes.any((shape) => shape.fill == 0xFFB08D57),
          isTrue,
          reason: 'slide ${i + 1} lost the head rule',
        );
      }
    });

    test('a table keeps its cells, its header and its widths', () {
      final frame = _slideOf(deck, 2).shapes.firstWhere(
        (shape) => shape.role == SlideRole.table,
      );
      final table = frame.blocks.whereType<TableBlock>().single;
      expect(table.rows.length, 5);
      expect(table.rows.first.header, isTrue);
      expect(table.rows.first.cells.map((c) => c.text), <String>[
        'Forme',
        'Sheets',
        'Waste',
        'Off at',
      ]);
      expect(table.rows[2].cells[1].text, '1,200');
      expect(table.columns.length, 4);
      expect(table.columns.first.width, greaterThan(100));
      // A header cell carries the fill the file gave it, resolved through the
      // theme like everything else.
      expect(table.rows.first.cells.first.background, 0xFF2E5E4E);
    });

    test('a picture keeps its bytes, its box and what it was called', () {
      final slide = _slideOf(deck, 3);
      final picture = slide.shapes.firstWhere(
        (shape) => shape.role == SlideRole.picture,
      );
      final image = picture.blocks.whereType<ImageBlock>().single;
      expect(deck.assets.containsKey(image.assetKey), isTrue);
      expect(deck.assets[image.assetKey]!.length, greaterThan(200));
      expect(image.alt, contains('forme two'));
      expect(picture.box.width, closeTo(6.4 * 72, 0.5));
      expect(picture.box.top, closeTo(2.1 * 72, 0.5));
    });

    test('speaker notes are kept off the slide and out of the count', () {
      final withNotes = _slideOf(deck, 4);
      expect(withNotes.notes, isNotEmpty);
      final said = withNotes.notes
          .whereType<ParagraphBlock>()
          .map((p) => p.text)
          .join(' ');
      expect(said, contains('docket rule'));
      // Nothing of the notes leaks onto the slide itself.
      expect(_allText(withNotes), isNot(contains('docket rule')));
      expect(_slideOf(deck, 0).notes, isEmpty);
    });

    test('the word count is what is on the slides', () {
      // Every slide carries the running foot, so the count is never zero, and
      // the notes are excluded, so it is not inflated either.
      expect(deck.wordCount, greaterThan(80));
      expect(deck.wordCount, lessThan(220));
    });

    test('the shapes of a slide arrive back to front', () {
      // The master's furniture first, then the layout's, then the slide's own,
      // which is the order they have to be painted in.
      final slide = _slideOf(deck, 1);
      final foot = slide.shapes.indexWhere(
        (shape) => shape.text.contains('michaelmas run'),
      );
      final title = slide.shapes.indexWhere(
        (shape) => shape.role == SlideRole.title,
      );
      expect(foot, lessThan(title));
    });

    test('every shape that speaks has somewhere to be drawn', () {
      for (var i = 0; i < deck.sections.length; i++) {
        for (final shape in _speaking(_slideOf(deck, i))) {
          expect(shape.box.width, greaterThan(0));
          expect(shape.box.height, greaterThan(0));
          expect(shape.box.left, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('the loader knows a deck when it sees one', () {
    test('by the part inside it, not by the name on it', () async {
      final bytes = await documentBytes(kPressDayBriefing);
      expect(DocumentLoader.sniff(bytes, 'press-day-briefing.pptx'), 'pptx');
      // Renamed on the way in, which happens constantly, and still a deck.
      expect(DocumentLoader.sniff(bytes, 'whatever.bin'), 'pptx');
    });

    test('a deck opens through the loader with no error', () async {
      final loaded = await loadedDocument(kPressDayBriefing);
      expect(loaded.failed, isFalse);
      expect(loaded.format, 'pptx');
      expect(loaded.document, isNotNull);
      expect(loaded.isPdf, isFalse);
    });
  });

  group('a deck that is not a deck', () {
    test('a name that promises a deck over bytes that are not', () {
      final bytes = Uint8List.fromList(utf8.encode('not a container at all'));
      final loaded = DocumentLoader.load(bytes, 'minutes.pptx');
      expect(loaded.failed, isTrue);
      expect(loaded.document, isNull);
    });

    test('a truncated container comes back as damaged, not as a crash',
        () async {
      final whole = await documentBytes(kPressDayBriefing);
      final cut = Uint8List.sublistView(whole, 0, whole.length ~/ 2);
      final loaded = DocumentLoader.load(cut, 'press-day-briefing.pptx');
      expect(loaded.failed, isTrue);
    });

    test('a zip with no presentation in it is a format error', () {
      // A valid zip holding one unrelated file. The parser has to say what is
      // wrong rather than throwing something the loader cannot classify.
      final bytes = _zipOf(<String, String>{'notes.txt': 'nothing to see'});
      expect(
        () => PptxParser(bytes).parse(),
        throwsA(isA<FormatException>()),
      );
    });

    test('a deck whose slides are all missing is a format error', () {
      final bytes = _zipOf(<String, String>{
        'ppt/presentation.xml':
            '<p:presentation xmlns:p="p"><p:sldIdLst/></p:presentation>',
      });
      expect(
        () => PptxParser(bytes).parse(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

/// A zip built on the spot, for the failures that need a container quire can
/// open and cannot read.
Uint8List _zipOf(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
