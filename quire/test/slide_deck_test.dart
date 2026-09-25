import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart' show Document, QuillController;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/pptx_deck.dart';
import 'package:quire/edit/pptx_text.dart';
import 'package:quire/edit/pptx_themes.dart';
import 'package:quire/format/pptx_parser.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/slide_sheet.dart';
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
  String resolve(String owner, String target) {
    final dir = owner.contains('/') ? owner.substring(0, owner.lastIndexOf('/')) : '';
    final steps = <String>[if (dir.isNotEmpty) ...dir.split('/')];
    for (final step in target.split('/')) {
      if (step == '..') {
        steps.removeLast();
      } else if (step.isNotEmpty && step != '.') {
        steps.add(step);
      }
    }
    return target.startsWith('/') ? target.substring(1) : steps.join('/');
  }
  for (final entry in parts.entries) {
    if (!entry.key.endsWith('.rels')) continue;
    final owner = entry.key.replaceFirst('_rels/', '').replaceFirst(RegExp(r'\.rels$'), '');
    for (final rel in XmlDocument.parse(entry.value).rootElement.childElements) {
      if (rel.getAttribute('TargetMode') == 'External') continue;
      final resolved = resolve(owner, rel.getAttribute('Target')!);
      expect(names.contains(resolved), isTrue, reason: '${entry.key} points at missing $resolved');
    }
  }
  final reached = <String>{'[Content_Types].xml'};
  final queue = <String>[''];
  while (queue.isNotEmpty) {
    final owner = queue.removeLast();
    final cut = owner.lastIndexOf('/');
    final rels = owner.isEmpty ? '_rels/.rels' : '${owner.substring(0, cut + 1)}_rels/${owner.substring(cut + 1)}.rels';
    final xml = parts[rels];
    if (xml == null) continue;
    reached.add(rels);
    for (final rel in XmlDocument.parse(xml).rootElement.childElements) {
      if (rel.getAttribute('TargetMode') == 'External') continue;
      final to = resolve(owner, rel.getAttribute('Target')!);
      if (reached.add(to)) queue.add(to);
    }
  }
  for (final name in names) {
    if (name.endsWith('/')) continue;
    expect(reached.contains(name), isTrue, reason: '$name is in the file with nothing pointing at it');
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

/// The sample deck with a clustered column chart, and no picture of it, on
/// its last slide.
Uint8List _charted(Uint8List bytes) {
  const chart = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart><c:autoTitleDeleted val="1"/><c:plotArea>'
      '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
      '<c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Monday</c:v></c:pt></c:strCache></c:strRef></c:tx>'
      '<c:cat><c:strRef><c:strCache><c:ptCount val="3"/><c:pt idx="0"><c:v>One</c:v></c:pt><c:pt idx="1"><c:v>Two</c:v></c:pt><c:pt idx="2"><c:v>Three</c:v></c:pt></c:strCache></c:strRef></c:cat>'
      '<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>1200</c:v></c:pt><c:pt idx="1"><c:v>1180</c:v></c:pt><c:pt idx="2"><c:v>900</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>'
      '<c:ser><c:idx val="1"/><c:order val="1"/><c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>Tuesday</c:v></c:pt></c:strCache></c:strRef></c:tx>'
      '<c:spPr><a:solidFill><a:srgbClr val="C0504D"/></a:solidFill></c:spPr>'
      '<c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>1100</c:v></c:pt><c:pt idx="2"><c:v>950</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>'
      '</c:barChart></c:plotArea><c:legend><c:legendPos val="b"/></c:legend></c:chart></c:chartSpace>';
  const frame = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="30" name="Chart 30"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="914400" y="1828800"/><a:ext cx="6096000" cy="3048000"/></p:xfrm><a:graphic>'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
      '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId9"/></a:graphicData></a:graphic></p:graphicFrame>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide6.xml') text = text!.replaceFirst('</p:spTree>', '$frame</p:spTree>');
    if (f.name == 'ppt/slides/_rels/slide6.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>',
      );
    }
    if (f.name == '[Content_Types].xml') {
      text = text!.replaceFirst(
        '</Types>',
        '<Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>',
      );
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  out.addFile(ArchiveFile.string('ppt/charts/chart1.xml', chart));
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with slide 2's body holding a plain paragraph, a
/// Japanese one in its own East Asian face, one with a link to a web page
/// and one to slide 6, and a second-level one in Georgia.
Uint8List _linked(Uint8List bytes) {
  const body = '<p:txBody><a:bodyPr/><a:lstStyle/>'
      '<a:p><a:r><a:rPr lang="en-GB"/><a:t>Forme three</a:t></a:r></a:p>'
      '<a:p><a:r><a:rPr lang="ja-JP" altLang="en-US"><a:ea typeface="MS Mincho"/></a:rPr><a:t>\u65E5\u672C\u8A9E\u306E\u30C6\u30AD\u30B9\u30C8\u3067\u3059</a:t></a:r></a:p>'
      '<a:p><a:r><a:rPr lang="en-GB"><a:hlinkClick r:id="rId2"/></a:rPr><a:t>Visit the site</a:t></a:r>'
      '<a:r><a:rPr lang="en-GB"/><a:t> or </a:t></a:r>'
      '<a:r><a:rPr lang="en-GB"><a:hlinkClick r:id="rId3" action="ppaction://hlinksldjump"/></a:rPr><a:t>jump to wrap up</a:t></a:r></a:p>'
      '<a:p><a:pPr lvl="1"/><a:r><a:rPr lang="en-GB" sz="2000"><a:latin typeface="Georgia"/></a:rPr><a:t>Second level in Georgia</a:t></a:r></a:p>'
      '</p:txBody>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    var text = f.name.endsWith('.xml') || f.name.endsWith('.rels') ? utf8.decode(f.content) : null;
    if (f.name == 'ppt/slides/slide2.xml') {
      final at = text!.indexOf('<p:txBody>', text.indexOf('name="Content 2"'));
      final end = text.indexOf('</p:txBody>', at) + '</p:txBody>'.length;
      text = text.replaceRange(at, end, body);
    }
    if (f.name == 'ppt/slides/_rels/slide2.xml.rels') {
      text = text!.replaceFirst(
        '</Relationships>',
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/" TargetMode="External"/>'
            '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slide6.xml"/></Relationships>',
      );
    }
    out.addFile(text == null ? ArchiveFile.bytes(f.name, f.content) : ArchiveFile.string(f.name, text));
  }
  return ZipEncoder().encodeBytes(out);
}

/// The sample deck with a table on its last slide that leaves its look
/// to PowerPoint's Medium Style 2 in the first accent: a heading row and
/// banded rows, no fills of its own.
Uint8List _styledTable(Uint8List bytes) {
  String row(String a, String b) => '<a:tr h="370840">'
      '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-GB"/><a:t>$a</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc>'
      '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-GB"/><a:t>$b</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc></a:tr>';
  final frame = '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="31" name="Table 31"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="914400" y="1828800"/><a:ext cx="4572000" cy="1112520"/></p:xfrm><a:graphic>'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>'
      '<a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr>'
      '<a:tblGrid><a:gridCol w="2286000"/><a:gridCol w="2286000"/></a:tblGrid>'
      '${row('Forme', 'Stock')}${row('One', 'Laid')}${row('Two', 'Wove')}'
      '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'ppt/slides/slide6.xml') {
      out.addFile(ArchiveFile.string(f.name, utf8.decode(f.content).replaceFirst('</p:spTree>', '$frame</p:spTree>')));
    } else {
      out.addFile(ArchiveFile.bytes(f.name, f.content));
    }
  }
  return ZipEncoder().encodeBytes(out);
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

    test('reads a chart with no picture of it from its cached values', () {
      final deck = PptxDeck(_charted(bytes));
      final shape = deck.shape(deck.slides[5], 30)!;
      final chart = shape.chart!;
      expect(chart.kind, 'col');
      expect(chart.categories, <String>['One', 'Two', 'Three']);
      expect(chart.series.map((s) => s.name), <String>['Monday', 'Tuesday']);
      expect(chart.series[1].values, <double?>[1100, null, 950]);
      expect(chart.series[1].colour, 0xFFC0504D);
      expect(chart.legend, isTrue);
      // A copy of the chart has a chart part of its own.
      final made = deck.paste(deck.slides[4], deck.copy(deck.slides[5], <int>{30})).single;
      final out = deck.write();
      _expectWhole(out);
      final again = PptxDeck(out);
      expect(again.shape(again.slides[4], made)!.chart!.series, hasLength(2));
      expect(_names(out).where((n) => n.startsWith('ppt/charts/chart')), hasLength(2));
    });

    testWidgets('a chart with no picture of it is drawn on its slide', (tester) async {
      final deck = PptxDeck(_charted(bytes));
      await tester.pumpWidget(MaterialApp(home: Center(child: SlideSheet(slide: deck.slide(deck.slides[5]), assets: deck.assets, width: 400))));
      final painters = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).map((w) => w.painter).whereType<SlideChartPainter>();
      expect(painters, hasLength(1));
      expect(painters.single.chart.series, hasLength(2));
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

  group('after the round one bar critic, the minors', () {
    test('a change that changes nothing is no step to undo', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final top = deck.objects(slide).last;
      deck.order(slide, top.id, SlideOrder.front);
      expect(deck.steps, 0);
      final theme = kSlideThemes[2];
      void paper() => deck.applyTheme(name: theme.name, colours: theme.colours, headings: theme.headings, body: theme.body, dark: theme.dark);
      paper();
      expect(deck.steps, 1);
      paper();
      expect(deck.steps, 1);
      deck.setFill(slide, top.id, 0xFF112233);
      deck.setFill(slide, top.id, 0xFF112233);
      expect(deck.steps, 2);
    });

    test('a picture takes brightness and contrast', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      deck.setPictureLight(slide, picture.id, brightness: 0.2, contrast: -0.2);
      expect(_parts(deck.write())['ppt/slides/slide4.xml'], contains('<a:lum bright="20000" contrast="-20000"/>'));
      _expectWhole(deck.write());
      final again = _reopen(deck);
      final shape = again.shape(again.slides[3], picture.id)!;
      expect(shape.brightness, closeTo(0.2, 1e-9));
      expect(shape.contrast, closeTo(-0.2, 1e-9));
    });

    testWidgets('a lightened picture is drawn lighter', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      final slide = deck.slides[3];
      final picture = deck.objects(slide).firstWhere((o) => o.isPicture);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      expect(find.byType(ColorFiltered), findsNothing);
      deck.setPictureLight(slide, picture.id, brightness: 0.4, contrast: 0);
      await tester.pumpWidget(MaterialApp(home: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 400)));
      final filter = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
      expect(filter.colorFilter, const ColorFilter.matrix(<double>[1, 0, 0, 0, 102, 0, 1, 0, 0, 102, 0, 0, 1, 0, 102, 0, 0, 0, 1, 0]));
    });

    test('a table in PowerPoint\'s own style is drawn in it', () {
      final deck = PptxDeck(_styledTable(bytes));
      final table = deck.slide(deck.slides[5]).shapes.expand((s) => s.blocks).whereType<TableBlock>().single;
      final accent = deck.themeColours(deck.masters.single)['accent1']!;
      final head = table.rows.first.cells.first;
      expect(head.background! & 0xFFFFFF, accent & 0xFFFFFF);
      final span = head.blocks.whereType<ParagraphBlock>().first.spans.first;
      expect(span.bold, isTrue);
      expect(span.color! & 0xFFFFFF, deck.themeColours(deck.masters.single)['lt1']! & 0xFFFFFF);
      final one = table.rows[1].cells.first.background;
      final two = table.rows[2].cells.first.background;
      expect(one, isNotNull);
      expect(two, isNotNull);
      expect(one, isNot(two));
      final looks = deck.looks(deck.slides[5], 31, cell: (0, 0))!;
      expect(looks.levels.first.bold, isTrue);
    });

    testWidgets('list numbers stand on one line in a slide as small as the strip draws', (tester) async {
      final deck = PptxDeck((await tester.runAsync(() => documentBytes(kPressDayBriefing)))!);
      final slide = deck.slides[1];
      final body = deck.objects(slide).firstWhere((o) => o.placeholder == 'body');
      final text = SlideText.read(deck.textBody(slide, body.id), deck.looks(slide, body.id)!);
      final ops = <Map<String, dynamic>>[
        for (var i = 1; i <= 12; i++) ...<Map<String, dynamic>>[
          <String, dynamic>{'insert': 'Point $i'},
          <String, dynamic>{'insert': '\n', 'attributes': <String, dynamic>{'list': 'ordered'}},
        ],
      ];
      deck.setText(slide, body.id, text.write(deck.slideDoc(slide), ops));
      await tester.pumpWidget(MaterialApp(home: Center(child: SlideSheet(slide: deck.slide(slide), assets: deck.assets, width: 100))));
      final marker = find.text('12.', findRichText: true);
      expect(marker, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(marker);
      final boxes = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3));
      expect(boxes.map((b) => b.top.round()).toSet(), hasLength(1));
    });
  });

  group('after the round one file critic', () {

    /// Edits slide 2's body of [deck] through the editor's own controller
    /// and saves the typing; returns the slide's written XML.
    String typeInBody(PptxDeck deck, void Function(QuillController c) edit) {
      final slide = deck.slides[1];
      final text = SlideText.read(deck.textBody(slide, 3), deck.looks(slide, 3)!);
      final c = QuillController(document: Document.fromJson(text.ops), selection: const TextSelection.collapsed(offset: 0));
      edit(c);
      deck.setText(slide, 3, text.write(deck.slideDoc(slide), c.document.toDelta().toJson()));
      final out = deck.write();
      _expectWhole(out);
      return _parts(out)['ppt/slides/slide2.xml']!;
    }

    List<XmlElement> paragraphs(String xml) {
      final doc = XmlDocument.parse(xml);
      final body = doc.rootElement.descendantElements.where((e) => e.name.local == 'sp').elementAt(1);
      return body.descendantElements.where((e) => e.name.local == 'p').toList();
    }

    String textOf(XmlElement p) => p.descendantElements.where((e) => e.name.local == 't').map((e) => e.innerText).join();

    XmlElement runWith(XmlElement p, String words) =>
        p.childElements.firstWhere((r) => r.name.local == 'r' && textOf(r).contains(words));

    int at(QuillController c, String words) => c.document.toPlainText().indexOf(words);

    test('a paragraph split before a link keeps that link on its words', () {
      final xml = typeInBody(PptxDeck(_linked(bytes)), (c) => c.replaceText(at(c, 'jump to'), 0, '\n', null));
      final ps = paragraphs(xml);
      expect(ps.map(textOf), <String>['Forme three', '\u65E5\u672C\u8A9E\u306E\u30C6\u30AD\u30B9\u30C8\u3067\u3059', 'Visit the site or ', 'jump to wrap up', 'Second level in Georgia']);
      expect(runWith(ps[3], 'jump').toXmlString(), contains('r:id="rId3"'));
      expect(runWith(ps[2], 'Visit').toXmlString(), contains('r:id="rId2"'));
      expect(runWith(ps[2], ' or ').toXmlString(), isNot(contains('hlinkClick')));
    });

    test('a line typed after a link is plain', () {
      final xml = typeInBody(PptxDeck(_linked(bytes)), (c) {
        final end = at(c, 'wrap up') + 'wrap up'.length;
        c.replaceText(end, 0, '\n', null);
        c.replaceText(end + 1, 0, 'A plain new point', null);
      });
      final ps = paragraphs(xml);
      expect(textOf(ps[3]), 'A plain new point');
      expect(ps[3].toXmlString(), isNot(contains('hlinkClick')));
      expect(runWith(ps[2], 'jump').toXmlString(), contains('r:id="rId3"'));
    });

    test('joined paragraphs keep each word its own face, language and link', () {
      final deck = PptxDeck(_linked(bytes));
      var xml = typeInBody(deck, (c) => c.replaceText(at(c, 'Visit') - 1, 1, '', null));
      var ps = paragraphs(xml);
      expect(ps, hasLength(3));
      final japanese = runWith(ps[1], '\u65E5\u672C').toXmlString();
      expect(japanese, contains('lang="ja-JP"'));
      expect(japanese, contains('<a:ea typeface="MS Mincho"/>'));
      expect(japanese, isNot(contains('hlinkClick')));
      expect(runWith(ps[1], 'Visit').toXmlString(), contains('r:id="rId2"'));
      xml = typeInBody(deck, (c) => c.replaceText(at(c, 'Second level') - 1, 1, '', null));
      ps = paragraphs(xml);
      final georgia = runWith(ps.last, 'Second level').toXmlString();
      expect(georgia, contains('<a:latin typeface="Georgia"/>'));
      expect(georgia, isNot(contains('hlinkClick')));
      expect(runWith(ps.last, 'jump').toXmlString(), contains('r:id="rId3"'));
    });

    test('a pasted control character is a line break or nothing, never a bad character', () {
      final deck = PptxDeck(bytes);
      final slide = deck.slides[0];
      final title = deck.objects(slide).firstWhere((o) => o.placeholder == 'ctrTitle' || o.placeholder == 'title');
      final text = SlideText.read(deck.textBody(slide, title.id), deck.looks(slide, title.id)!);
      final c = QuillController(document: Document.fromJson(text.ops), selection: const TextSelection.collapsed(offset: 0));
      final controls = String.fromCharCodes(<int>[for (var u = 0; u < 0x20; u++) if (u != 0x09 && u != 0x0A && u != 0x0D && u != 0x0B) u]);
      c.replaceText(0, 0, 'Line one\u000Bline two$controls ', null);
      deck.setText(slide, title.id, text.write(deck.slideDoc(slide), c.document.toDelta().toJson()));
      final xml = _parts(deck.write())['ppt/slides/slide1.xml']!;
      expect(RegExp(r'&#x?[0-9A-Fa-f]+;').hasMatch(xml), isFalse);
      expect(xml.runes.where((u) => u < 0x20 && u != 0x09 && u != 0x0A && u != 0x0D), isEmpty);
      expect(xml, contains('<a:t>Line one</a:t></a:r><a:br>'));
      expect(xml, contains('<a:t>line two '));
    });
    test('a deleted slide takes the parts only it pointed at', () {
      final deck = PptxDeck(bytes);
      deck.deleteSlides(<String>{deck.slides[3]});
      final out = deck.write();
      _expectWhole(out);
      expect(_names(out), isNot(contains('ppt/media/image1.png')));
      final charted = PptxDeck(_charted(bytes));
      final clip = charted.copySlides(<String>[charted.slides[5]]);
      charted.deleteSlides(<String>{charted.slides[5]}, label: 'Cut');
      charted.pasteSlides(clip, 0);
      final pasted = charted.write();
      _expectWhole(pasted);
      expect(_names(pasted).where((n) => n.startsWith('ppt/charts/')), hasLength(1));
      expect(_parts(pasted)['[Content_Types].xml'], isNot(contains('/ppt/charts/chart1.xml')));
    });
  });
}
