import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/pptx_deck.dart';
import 'package:quire/edit/pptx_text.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:xml/xml.dart';

import 'support/fixtures.dart';

Map<String, String> _parts(Uint8List bytes) => <String, String>{
  for (final f in ZipDecoder().decodeBytes(bytes).files)
    if (f.isFile && (f.name.endsWith('.xml') || f.name.endsWith('.rels')))
      f.name: utf8.decode(f.content),
};

Set<String> _names(Uint8List bytes) => <String>{
  for (final f in ZipDecoder().decodeBytes(bytes).files) f.name,
};

/// The deck as a fresh reader sees it after a save.
PptxDeck _reopen(PptxDeck deck) => PptxDeck(deck.write());

/// Every relationship of every part points at a part the package holds,
/// and every part has a content type.
void _expectWhole(Uint8List bytes) {
  final names = _names(bytes);
  final parts = _parts(bytes);
  final types = XmlDocument.parse(parts['[Content_Types].xml']!).rootElement;
  final overrides = <String>{
    for (final e in types.childElements)
      if (e.name.local == 'Override') e.getAttribute('PartName')!.substring(1),
  };
  final defaults = <String>{
    for (final e in types.childElements)
      if (e.name.local == 'Default') e.getAttribute('Extension')!.toLowerCase(),
  };
  for (final name in names) {
    if (name.endsWith('/')) continue;
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    expect(overrides.contains(name) || defaults.contains(ext), isTrue, reason: '$name has no content type');
  }
  for (final o in overrides) {
    expect(names.contains(o), isTrue, reason: 'content type for missing $o');
  }
  for (final entry in parts.entries) {
    if (!entry.key.endsWith('.rels')) continue;
    final owner = entry.key.replaceFirst('_rels/', '').replaceFirst(RegExp(r'\.rels$'), '');
    for (final rel in XmlDocument.parse(entry.value).rootElement.childElements) {
      if (rel.getAttribute('TargetMode') == 'External') continue;
      final target = rel.getAttribute('Target')!;
      final dir = owner.contains('/') ? owner.substring(0, owner.lastIndexOf('/')) : '';
      final parts = <String>[if (dir.isNotEmpty) ...dir.split('/')];
      for (final step in target.split('/')) {
        if (step == '..') {
          parts.removeLast();
        } else if (step.isNotEmpty && step != '.') {
          parts.add(step);
        }
      }
      final resolved = target.startsWith('/') ? target.substring(1) : parts.join('/');
      expect(names.contains(resolved), isTrue, reason: '${entry.key} points at missing $resolved');
    }
  }
}

/// The sample deck with its six slides in two PowerPoint sections, three
/// each.
Uint8List _sectioned(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/presentation.xml') {
      final xml = utf8.decode(f.content).replaceFirst(
        '</p:presentation>',
        '<p:extLst><p:ext uri="{521415D9-36F7-43E2-AB2F-B90AF26B5E84}">'
            '<p14:sectionLst xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main">'
            '<p14:section name="One" id="{11111111-1111-1111-1111-111111111111}"><p14:sldIdLst>'
            '<p14:sldId id="256"/><p14:sldId id="257"/><p14:sldId id="258"/></p14:sldIdLst></p14:section>'
            '<p14:section name="Two" id="{22222222-2222-2222-2222-222222222222}"><p14:sldIdLst>'
            '<p14:sldId id="259"/><p14:sldId id="260"/><p14:sldId id="261"/></p14:sldIdLst></p14:section>'
            '</p14:sectionLst></p:ext></p:extLst></p:presentation>',
      );
      out.addFile(ArchiveFile.string(f.name, xml));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
}

/// Each section's slide ids, in order.
List<List<String>> _sections(Uint8List bytes) {
  final xml = XmlDocument.parse(_parts(bytes)['ppt/presentation.xml']!);
  return <List<String>>[
    for (final section in xml.rootElement.descendantElements.where((e) => e.name.local == 'section'))
      <String>[
        for (final id in section.descendantElements.where((e) => e.name.local == 'sldId')) id.getAttribute('id')!,
      ],
  ];
}

void main() {
  late Uint8List bytes;

  setUpAll(() async {
    bytes = await documentBytes(kPressDayBriefing);
  });

  group('the deck model', () {
    test('writes back the very bytes it read when nothing changed', () {
      final deck = PptxDeck(bytes);
      expect(deck.slides.length, 6);
      expect(deck.write(), same(bytes));
    });

    test('moves, sizes and turns a shape, and undo takes each step back', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.place(slide, picture.id, const SlideBox(100, 120, 300, 200));
      deck.place(slide, picture.id, const SlideBox(100, 120, 300, 200), rotation: 30);
      final again = _reopen(deck);
      final moved = again.object(again.slides[3], picture.id)!;
      expect(moved.box, const SlideBox(100, 120, 300, 200));
      expect(moved.rotation, closeTo(30, 0.01));
      deck.undo();
      expect(deck.object(slide, picture.id)!.rotation, 0);
      deck.undo();
      expect(deck.object(slide, picture.id)!.box, picture.box);
      expect(deck.write(), same(bytes));
      deck.redo();
      expect(deck.object(slide, picture.id)!.box, const SlideBox(100, 120, 300, 200));
    });

    test('moving a placeholder gives it a box of its own', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final title = deck.objects(slide).firstWhere((o) => o.placeholder == 'title');
      deck.place(slide, title.id, SlideBox(title.box.left + 40, title.box.top, title.box.width, title.box.height));
      final again = _reopen(deck);
      expect(again.object(again.slides[1], title.id)!.box.left, closeTo(title.box.left + 40, 0.01));
      final shape = again.slide(again.slides[1]).shapes.firstWhere((s) => s.id == title.id);
      expect(shape.text, 'What changes today');
    });

    test('deletes a shape, and copies one onto another slide with its picture', () {
      final deck = PptxDeck(bytes);
      final from = deck.slides[3];
      final to = deck.slides[5];
      final picture = deck.objects(from).firstWhere((o) => o.isPicture);
      final clip = deck.copy(from, <int>{picture.id});
      final made = deck.paste(to, clip);
      expect(made, hasLength(1));
      deck.delete(from, <int>{picture.id});
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      expect(again.objects(again.slides[3]).where((o) => o.isPicture), isEmpty);
      final pasted = again.slide(again.slides[5]).shapes.where((s) => s.blocks.any((b) => b is ImageBlock));
      expect(pasted, hasLength(1));
      final image = pasted.single.blocks.whereType<ImageBlock>().single;
      expect(again.assets[image.assetKey], isNotNull);
    });

    test('a pasted copy on its own slide lands down and to the right', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final made = deck.duplicate(slide, <int>{caption.id}).single;
      final copy = deck.object(slide, made)!;
      expect(copy.box.left, closeTo(caption.box.left + 10, 0.01));
      expect(copy.box.top, closeTo(caption.box.top + 10, 0.01));
      expect(deck.shape(slide, made)!.text, deck.shape(slide, caption.id)!.text);
    });

    test('a copied placeholder states its own box and look', () {
      final deck = PptxDeck(bytes);
      final from = deck.slides[1];
      final body = deck.objects(from).firstWhere((o) => o.placeholder == 'body');
      final was = deck.shape(from, body.id)!;
      final made = deck.paste(deck.slides[3], deck.copy(from, <int>{body.id})).single;
      final again = _reopen(deck);
      final pasted = again.shape(again.slides[3], made)!;
      expect(pasted.box, was.box);
      final wasItems = was.blocks.whereType<ListItemBlock>().toList();
      final nowItems = pasted.blocks.whereType<ListItemBlock>().toList();
      expect(nowItems.length, wasItems.length);
      expect(nowItems.first.spans.first.fontSize, wasItems.first.spans.first.fontSize);
      expect(nowItems[2].level, 1);
    });

    test('adds a slide from a layout, with the layout placeholders empty', () {
      final deck = PptxDeck(bytes);
      final layout = deck.layouts.firstWhere((l) => l.type == 'obj');
      final made = deck.addSlide(layout.path, 2);
      expect(deck.slides.length, 7);
      expect(deck.slides[2], made);
      final objects = deck.objects(made);
      expect(objects.map((o) => o.placeholder), containsAll(<String>['title', 'body']));
      final out = deck.write();
      _expectWhole(out);
      final reread = PptxParser(out).parse();
      expect(reread.sections.length, 7);
    });

    test('duplicates a slide with its notes, and deletes slides cleanly', () {
      final deck = PptxDeck(bytes);
      final first = deck.slides.first;
      final noted = deck.slides[4];
      final made = deck.duplicateSlides(<String>[noted]).single;
      expect(deck.slides[5], made);
      final reread = PptxParser(deck.write()).parse();
      final notes = reread.sections[5].blocks.whereType<SlideBlock>().single.notes;
      expect(notes, isNotEmpty);
      expect(notes.length, reread.sections[4].blocks.whereType<SlideBlock>().single.notes.length);
      final copyNotes = _parts(deck.write()).entries.where((e) => e.key.startsWith('ppt/notesSlides/_rels/') && e.value.contains(made.split('/').last));
      expect(copyNotes, hasLength(1));
      deck.deleteSlides(<String>{first, deck.slides[2]});
      expect(deck.slides, isNot(contains(first)));
      final out = deck.write();
      _expectWhole(out);
      expect(_names(out).contains(first), isFalse);
      final after = PptxParser(out).parse();
      expect(after.sections.length, 5);
      expect(after.sections.first.title, 'What changes today');
    });

    test('keeps PowerPoint\'s sections in step with the slides', () {
      final deck = PptxDeck(_sectioned(bytes));
      final order = deck.slides;
      deck.deleteSlides(<String>{order[1]});
      expect(_sections(deck.write()), <List<String>>[
        <String>['256', '258'],
        <String>['259', '260', '261'],
      ]);
      deck.moveSlides(<String>[order[5]], 0);
      expect(_sections(deck.write()), <List<String>>[
        <String>['261', '256', '258'],
        <String>['259', '260'],
      ]);
      final layout = deck.layouts.first.path;
      deck.addSlide(layout, 3);
      expect(_sections(deck.write()), <List<String>>[
        <String>['261', '256', '258', '262'],
        <String>['259', '260'],
      ]);
      _expectWhole(deck.write());
    });

    test('never deletes the last slide', () {
      final deck = PptxDeck(bytes);
      deck.deleteSlides(deck.slides.toSet());
      expect(deck.slides.length, 6);
      expect(deck.canUndo, isFalse);
    });

    test('moves slides together to a new place', () {
      final deck = PptxDeck(bytes);
      final order = deck.slides;
      deck.moveSlides(<String>[order[4], order[1]], 0);
      expect(deck.slides, <String>[order[1], order[4], order[0], order[2], order[3], order[5]]);
      final reread = PptxParser(deck.write()).parse();
      expect(reread.sections[1].title, PptxParser(bytes).parse().sections[4].title);
    });

    test('cut slides paste back after their neighbours are gone', () {
      final deck = PptxDeck(bytes);
      final order = deck.slides;
      final clip = deck.copySlides(<String>[order[0]]);
      deck.deleteSlides(<String>{order[0]});
      final made = deck.pasteSlides(clip, 3);
      expect(deck.slides[3], made.single);
      final out = deck.write();
      _expectWhole(out);
      expect(PptxParser(out).parse().sections[3].title, 'Press Day Briefing');
    });

    test('fills, outlines, dashes and shadows a shape, and fades a picture', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.setFill(slide, caption.id, 0xFF336699);
      deck.setLineColour(slide, caption.id, 0xFFCC0000);
      deck.setLineWeight(slide, caption.id, 3);
      deck.setLineDash(slide, caption.id, 'dash');
      deck.setShadowed(slide, caption.id, true);
      deck.setOpacity(slide, picture.id, 0.5);
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], caption.id)!;
      expect(shape.fill, 0xFF336699);
      expect(shape.line, 0xFFCC0000);
      expect(shape.lineWidth, 3);
      expect(shape.dash, 'dash');
      expect(shape.shadow, isTrue);
      expect(again.shape(again.slides[3], picture.id)!.opacity, closeTo(0.5, 0.001));
      final xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      // noFill made way for the new fill, and the order is the schema's.
      expect(xml, isNot(contains('<a:noFill/><a:solidFill>')));
      expect(xml.indexOf('<a:solidFill><a:srgbClr val="336699"/>'), lessThan(xml.indexOf('<a:ln ')));
    });

    test('adds a text box, a shape, a line and a picture', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[5];
      final box = deck.addTextBox(slide, const SlideBox(100, 100, 300, 40));
      final shape = deck.addShape(slide, 'ellipse', const SlideBox(400, 100, 120, 120));
      final line = deck.addLine(slide, (500, 400), (100, 300));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      );
      final picture = deck.addPicture(slide, png, 'png', const SlideBox(10, 10, 50, 50));
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      final s = again.slides[5];
      expect(again.object(s, box)!.hasText, isTrue);
      expect(again.shape(s, shape)!.geometry, 'ellipse');
      final drawn = again.object(s, line)!;
      expect(drawn.isLine, isTrue);
      expect(drawn.flipH, isTrue);
      expect(drawn.flipV, isTrue);
      expect(drawn.box, const SlideBox(100, 300, 400, 100));
      expect(again.object(s, picture)!.isPicture, isTrue);
      expect(again.shape(s, picture)!.blocks.whereType<ImageBlock>().single.assetKey, startsWith('ppt/media/'));
    });

    test('moves a shape through the stack', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final ids = deck.objects(slide).map((o) => o.id).toList();
      deck.order(slide, ids.last, SlideOrder.back);
      expect(deck.objects(slide).map((o) => o.id).first, ids.last);
      deck.order(slide, ids.last, SlideOrder.front);
      expect(deck.objects(slide).map((o) => o.id).toList(), ids);
    });

    test('a slide can be moved to another layout, and given its own ground', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final title = deck.layouts.firstWhere((l) => l.type == 'title');
      deck.setLayout(slide, title.path);
      expect(deck.layoutOf(slide), title.path);
      deck.setBackground(slide, 0xFF223344);
      final again = _reopen(deck);
      expect(again.slide(again.slides[1]).background, 0xFF223344);
    });

    test('a theme gives every master its colours and faces', () {
      final deck = PptxDeck(bytes);
      final master = deck.masters.single;
      deck.applyTheme(
        name: 'Night',
        colours: const <String, int>{'dk1': 0x101010, 'lt1': 0xFAFAFA, 'accent1': 0x2266CC},
        headings: 'Arial',
        body: 'Arial',
        dark: true,
      );
      final again = _reopen(deck);
      expect(again.themeName(master), 'Night');
      expect(again.themeColours(master)['accent1'], 0x2266CC);
      // A dark theme sets its dark colour as the ground.
      expect(again.slide(again.slides[0]).background, 0xFF101010);
    });
  });

  group('slide text', () {
    SlideText read(PptxDeck deck, String slide, int id) =>
        SlideText.read(deck.textBody(slide, id), deck.looks(slide, id)!);

    test('reads each paragraph as a line with its level and list', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final lines = Delta.fromJson(text.ops).toList().where((op) => op.data == '\n').toList();
      expect(lines, hasLength(5));
      expect(lines[0].attributes, <String, dynamic>{'list': 'bullet'});
      expect(lines[2].attributes, <String, dynamic>{'indent': 1, 'list': 'bullet'});
    });

    test('an unchanged text body writes back paragraph for paragraph', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final written = text.write(deck.slideDoc(slide), text.ops);
      expect(written.toXmlString(), deck.textBody(slide, body.id)!.toXmlString());
    });

    test('typing keeps each run its own properties and changes only the words', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final doc = Delta.fromJson(text.ops);
      final edited = doc.compose(Delta()..retain(7)..insert('late ', <String, dynamic>{'size': '18'}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], caption.id)!;
      expect(shape.text, startsWith('Pulled late at 09:40'));
      final xml = _parts(again.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:rPr lang="en-GB" sz="1800"/><a:t>Pulled late at 09:40, before the reset.</a:t>'));
      // The second paragraph was not touched and is written as it was.
      expect(xml, contains('<a:p><a:pPr><a:buNone/></a:pPr><a:r><a:rPr lang="en-GB" sz="1800"></a:rPr><a:t>The gutter'));
    });

    test('bold on one word writes b on that run alone', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final edited = Delta.fromJson(text.ops).compose(Delta()..retain(7)..retain(2, <String, dynamic>{'bold': true}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final xml = _parts(deck.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:r><a:rPr lang="en-GB" sz="1800" b="1"/><a:t>at</a:t></a:r>'));
      expect(xml, contains('<a:t>Pulled </a:t>'));
    });

    test('a line break inside a paragraph stays one', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final caption = deck.objects(slide).firstWhere((o) => o.name == 'Caption');
      final text = read(deck, slide, caption.id);
      final edited = Delta.fromJson(text.ops).compose(Delta()..retain(6)..insert(kSlideBreak, <String, dynamic>{'size': '18'}));
      deck.setText(slide, caption.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final looks = again.looks(again.slides[3], caption.id)!;
      expect(looks.paragraphs, hasLength(2));
      final xml = _parts(again.write())['ppt/slides/slide4.xml']!;
      expect(xml, contains('<a:t>Pulled</a:t></a:r><a:br><a:rPr lang="en-GB" sz="1800"/></a:br><a:r>'));
    });

    test('indenting a bullet moves it to the next level and drops its own margin', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = read(deck, slide, body.id);
      final first = Delta.fromJson(text.ops).toList().first.data as String;
      final edited = Delta.fromJson(text.ops).compose(
        Delta()
          ..retain(first.length)
          ..retain(1, <String, dynamic>{'indent': 1}),
      );
      deck.setText(slide, body.id, text.write(deck.slideDoc(slide), edited.toJson()));
      final again = _reopen(deck);
      final items = again.shape(again.slides[1], body.id)!.blocks.whereType<ListItemBlock>().toList();
      expect(items.first.level, 1);
      expect(items.first.marker, '–');
      expect(items.first.spans.first.fontSize, 17);
    });
  });
}
