import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/docx_delta.dart';
import 'package:xml/xml.dart';

import 'support/fixtures.dart';

const _namespaces = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
    'xmlns:v="urn:schemas-microsoft-com:vml" '
    'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" '
    'xmlns:w16se="http://schemas.microsoft.com/office/word/2015/wordml/symex" '
    'mc:Ignorable="w14 w16se"';

const _landscape = '<w:sectPr><w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/></w:sectPr>';

/// A Word package holding [body], with the styles, numbering and document
/// relationships given.
Uint8List docx(String body, {String styles = '', String numbering = '', String rels = '', String sectPr = _landscape}) {
  const main = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '${numbering.isEmpty ? '' : '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'}'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>',
    'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '${numbering.isEmpty ? '' : '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'}'
        '$rels'
        '</Relationships>',
    'word/document.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_namespaces><w:body>$body$sectPr</w:body></w:document>',
    'word/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="$main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>'
        '$styles</w:styles>',
    if (numbering.isNotEmpty)
      'word/numbering.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:numbering xmlns:w="$main">$numbering</w:numbering>',
  };
  final archive = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String documentXml(Uint8List bytes, [String part = 'word/document.xml']) =>
    utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(part)!.content as List<int>);

List<XmlElement> bodyOf(Uint8List bytes) =>
    XmlDocument.parse(documentXml(bytes)).rootElement.getElement('w:body')!.childElements.toList();

String textOf(XmlElement e) => e.descendantElements.where((d) => d.name.local == 't').map((d) => d.innerText).join();

XmlElement paragraphWith(Uint8List bytes, String words) =>
    bodyOf(bytes).firstWhere((p) => p.name.local == 'p' && textOf(p).contains(words));

/// A document opened as the editor opens it.
class Opened {
  Opened(this.bytes) : delta = DocxDelta.read(bytes) {
    doc = Document.fromJson(delta.ops);
  }

  final Uint8List bytes;
  final DocxDelta delta;
  late final Document doc;

  int at(String words) {
    final i = doc.toPlainText().indexOf(words);
    expect(i, isNonNegative, reason: words);
    return i;
  }

  void type(String before, String text) => doc.insert(at(before), text);

  /// Enter pressed at the end of the line holding [words], then [text] typed.
  void enterAfter(String words, String text) {
    final end = at(words) + words.length;
    doc.insert(end, '\n');
    doc.insert(end + 1, text);
  }

  Uint8List save() => delta.write(<Map<String, Object?>>[
        for (final op in doc.toDelta().toJson()) Map<String, Object?>.from(op as Map),
      ]);
}

void main() {
  group('what a run holds that the editor does not change', () {
    const textBox = '<w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wp:inline>'
        '<wp:extent cx="914400" cy="457200"/><a:graphic><a:graphicData uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
        '<wps:wsp><wps:txbx><w:txbxContent><w:p><w:r><w:t>TEXTBOX CONTENT</w:t></w:r></w:p></w:txbxContent></wps:txbx></wps:wsp>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></mc:Choice><mc:Fallback><w:pict><v:shape><v:textbox>'
        '<w:txbxContent><w:p><w:r><w:t>TEXTBOX CONTENT</w:t></w:r></w:p></w:txbxContent></v:textbox></v:shape></w:pict>'
        '</mc:Fallback></mc:AlternateContent></w:r>';
    const emoji = '<w:r><mc:AlternateContent><mc:Choice Requires="w16se"><w16se:symEx w16se:font="Segoe UI Emoji" w16se:char="1F389"/>'
        '</mc:Choice><mc:Fallback><w:t>\u{1F389}</w:t></mc:Fallback></mc:AlternateContent></w:r>';

    test('a text box and an emoji written as alternate content survive typing beside them', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">The box is anchored here. </w:t></w:r>$textBox'
        '<w:r><w:t>Anchor text continues.</w:t></w:r></w:p>'
        '<w:p><w:r><w:t xml:space="preserve">Party time </w:t></w:r>$emoji<w:r><w:t xml:space="preserve"> see you.</w:t></w:r></w:p>',
      ));
      expect(file.doc.toPlainText(), contains('\u{1F389}'.isEmpty ? '' : '￼'));
      file.type('Anchor text', 'EDITED ');
      file.type(' see you', ' and');
      final saved = file.save();
      final xml = documentXml(saved);
      expect(xml, contains('EDITED Anchor text continues.'));
      final boxes = XmlDocument.parse(xml).descendantElements.where((e) => e.name.local == 'AlternateContent').toList();
      expect(boxes, hasLength(2));
      expect(boxes.first.toXmlString(), XmlDocument.parse('<w:root $_namespaces>$textBox</w:root>')
          .rootElement.descendantElements.firstWhere((e) => e.name.local == 'AlternateContent').toXmlString());
      expect(textOf(boxes.last), '\u{1F389}');
    });

    test('ruby, symbols from a symbol font and a right-aligned tab are kept, and shown as what they draw', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">Before </w:t></w:r>'
        '<w:r><w:ruby><w:rubyPr/><w:rt><w:r><w:t>かんじ</w:t></w:r></w:rt><w:rubyBase><w:r><w:t>漢字</w:t></w:r></w:rubyBase></w:ruby></w:r>'
        '<w:r><w:t xml:space="preserve"> done </w:t></w:r><w:r><w:sym w:font="Wingdings" w:char="F0FC"/></w:r>'
        '<w:r><w:t xml:space="preserve"> arrow </w:t></w:r><w:r><w:sym w:font="Symbol" w:char="F0AE"/></w:r>'
        '<w:r><w:ptab w:relativeTo="margin" w:alignment="right" w:leader="none"/></w:r><w:r><w:t>right side</w:t></w:r></w:p>',
      ));
      final shown = <String>[
        for (final kept in file.delta.inlines.values) kept.text,
      ];
      expect(shown, containsAll(<String>['漢字', '✔', '→', '\t']));
      file.type('Before', 'NEW ');
      final saved = file.save();
      final paragraph = paragraphWith(saved, 'NEW Before');
      final kinds = paragraph.descendantElements.map((e) => e.name.local).toSet();
      expect(kinds, containsAll(<String>['ruby', 'rubyBase', 'sym', 'ptab']));
      final syms = paragraph.descendantElements.where((e) => e.name.local == 'sym').toList();
      expect(syms.map((e) => e.getAttribute('w:char')), <String>['F0FC', 'F0AE']);
    });

    test('a tracked insertion stays a tracked insertion when words beside it change', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">Alpha </w:t></w:r>'
        '<w:ins w:id="1" w:author="Reviewer" w:date="2024-01-01T00:00:00Z"><w:r><w:t xml:space="preserve">inserted words </w:t></w:r></w:ins>'
        '<w:r><w:t xml:space="preserve">Bravo </w:t></w:r>'
        '<w:del w:id="2" w:author="Reviewer" w:date="2024-01-01T00:00:00Z"><w:r><w:delText>gone</w:delText></w:r></w:del>'
        '<w:r><w:t>Charlie.</w:t></w:r></w:p>',
      ));
      file.type('Charlie', 'NEW ');
      final paragraph = paragraphWith(file.save(), 'NEW Charlie');
      final ins = paragraph.descendantElements.firstWhere((e) => e.name.local == 'ins');
      expect(ins.getAttribute('w:author'), 'Reviewer');
      expect(textOf(ins), 'inserted words ');
      expect(paragraph.descendantElements.where((e) => e.name.local == 'del'), hasLength(1));
    });

    test('a bookmark and a comment on one word stay on that word when the paragraph is edited', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">The </w:t></w:r><w:bookmarkStart w:id="0" w:name="TargetWord"/>'
        '<w:commentRangeStart w:id="3"/><w:r><w:t>target</w:t></w:r><w:bookmarkEnd w:id="0"/><w:commentRangeEnd w:id="3"/>'
        '<w:r><w:t xml:space="preserve"> word sits here.</w:t></w:r><w:r><w:commentReference w:id="3"/></w:r></w:p>',
      ));
      file.type('sits', 'NEW ');
      final paragraph = paragraphWith(file.save(), 'NEW sits');
      String between(String start, String end) {
        final out = StringBuffer();
        var inside = false;
        for (final e in paragraph.descendantElements) {
          if (e.name.local == start) inside = true;
          if (e.name.local == end) inside = false;
          if (inside && e.name.local == 't') out.write(e.innerText);
        }
        return out.toString();
      }

      expect(between('bookmarkStart', 'bookmarkEnd'), 'target');
      expect(between('commentRangeStart', 'commentRangeEnd'), 'target');
    });

    test('a field across paragraphs, like a table of contents, is kept whole and shows its entries', () {
      final body = '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" </w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>Introduction</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>1</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Methods</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>2</w:t></w:r></w:p>'
          '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
          '<w:p><w:r><w:t>Page text.</w:t></w:r></w:p>';
      final file = Opened(docx(body));
      final field = file.delta.blocks.values.single;
      expect(field.kind, 'field');
      expect(field.lines, <String>['Introduction\t1', 'Methods\t2', '']);
      file.type('Page text', 'More ');
      final xml = documentXml(file.save());
      expect(xml, contains(body.substring(0, body.indexOf('<w:p><w:r><w:t>Page text.'))));
    });

    test('bold and italic on right-to-left words are written for those words too', () {
      final file = Opened(docx(
        '<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rtl/></w:rPr><w:t>عربي</w:t></w:r></w:p>',
      ));
      file.doc.format(file.at('عربي'), 4, Attribute.bold);
      file.doc.format(file.at('عربي'), 4, Attribute.italic);
      final rPr = paragraphWith(file.save(), 'عربي').descendantElements.firstWhere((e) => e.name.local == 'rPr');
      final tags = rPr.childElements.map((e) => e.name.local).toList();
      expect(tags, containsAll(<String>['b', 'bCs', 'i', 'iCs', 'rtl']));
      expect(DocxDelta.read(file.save()).ops.firstWhere((o) => o['insert'] == 'عربي')['attributes'],
          containsPair('bold', true));
    });

    test('new run properties go before a tracked formatting change, as the schema has it', () {
      final file = Opened(docx(
        '<w:p><w:r><w:rPr><w:b/><w:rPrChange w:id="5" w:author="A" w:date="2024-01-01T00:00:00Z"><w:rPr/></w:rPrChange></w:rPr>'
        '<w:t>reviewed</w:t></w:r><w:r><w:t xml:space="preserve"> text</w:t></w:r></w:p>',
      ));
      file.doc.format(file.at('reviewed'), 8, const ColorAttribute('#CC0000'));
      file.doc.format(file.at('reviewed'), 8, Attribute.underline);
      final rPr = paragraphWith(file.save(), 'reviewed').descendantElements.firstWhere((e) => e.name.local == 'rPr');
      final tags = rPr.childElements.map((e) => e.name.local).toList();
      expect(tags.last, 'rPrChange');
      expect(tags, containsAll(<String>['color', 'u']));
    });

    test('clearing formatting takes direct size and typeface off in the file too', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">Plain start </w:t></w:r>'
        '<w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:b/><w:color w:val="FF0000"/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr>'
        '<w:t>BIG RED WORDS</w:t></w:r><w:r><w:t xml:space="preserve"> plain end.</w:t></w:r></w:p>',
      ));
      final at = file.at('BIG RED WORDS');
      for (final attribute in <Attribute>[Attribute.bold, Attribute.color, Attribute.size, Attribute.font]) {
        file.doc.format(at, 13, Attribute.clone(attribute, null));
      }
      final saved = file.save();
      final run = paragraphWith(saved, 'BIG RED WORDS').descendantElements
          .firstWhere((e) => e.name.local == 'r' && textOf(e) == 'BIG RED WORDS');
      final tags = run.getElement('w:rPr')?.childElements.map((e) => e.name.local).toList() ?? const <String>[];
      expect(tags, isNot(contains('sz')));
      expect(tags, isNot(contains('b')));
      expect(tags, isNot(contains('color')));
      expect(run.getElement('w:rPr')?.getElement('w:rFonts')?.getAttribute('w:ascii'), isNull);
      final op = DocxDelta.read(saved).ops.firstWhere((o) => (o['insert'] as String?)?.contains('BIG RED WORDS') ?? false);
      expect(op['insert'], 'Plain start BIG RED WORDS plain end.');
      expect(op['attributes'], isNull);
    });

    test('a link keeps its tooltip when its paragraph is edited', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t xml:space="preserve">See </w:t></w:r><w:hyperlink r:id="rId9" w:tooltip="Go there" w:history="1">'
        '<w:r><w:t>the site</w:t></w:r></w:hyperlink><w:r><w:t>.</w:t></w:r></w:p>',
        rels: '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
            'Target="https://example.com/" TargetMode="External"/>',
      ));
      file.type('See', 'Please ');
      final link = paragraphWith(file.save(), 'Please See').descendantElements.firstWhere((e) => e.name.local == 'hyperlink');
      expect(link.getAttribute('w:tooltip'), 'Go there');
      expect(link.getAttribute('w:history'), '1');
      expect(textOf(link), 'the site');
    });

    test('paragraphs nobody touched are written back as the very text they were read from', () {
      const untouched = '<w:p><w:r><w:t xml:space="preserve">a &gt; b and c &lt; d</w:t></w:r><w:fldSimple w:instr="DATE&#10;"><w:r><w:t>today</w:t></w:r></w:fldSimple></w:p>';
      final file = Opened(docx('<w:p><w:r><w:t>First paragraph.</w:t></w:r></w:p>$untouched'));
      file.type('First', 'Edited ');
      final xml = documentXml(file.save());
      expect(xml, contains(untouched));
      expect(xml, contains(_landscape));
    });
  });

  group('section breaks', () {
    const coverBreak = '<w:p><w:pPr><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:pPr></w:p>';
    const cover = '<w:p><w:r><w:t>Cover title</w:t></w:r></w:p><w:p><w:r><w:t>Cover subtitle paragraph.</w:t></w:r></w:p>';
    const bodyText = '<w:p><w:r><w:t>Body heading</w:t></w:r></w:p><w:p><w:r><w:t>Body paragraph one.</w:t></w:r></w:p>';

    List<String> sectioned(Uint8List bytes) => <String>[
          for (final p in bodyOf(bytes))
            if (p.name.local == 'p' && p.getElement('w:pPr')?.getElement('w:sectPr') != null) textOf(p),
        ];

    test('deleting a blank line before a break leaves the break where it was', () {
      final file = Opened(docx('$cover<w:p/>$coverBreak$bodyText'));
      final blank = file.at('Cover subtitle paragraph.') + 'Cover subtitle paragraph.'.length;
      file.doc.delete(blank, 1);
      final saved = file.save();
      expect(sectioned(saved), <String>['']);
      final texts = <String>[for (final p in bodyOf(saved)) if (p.name.local == 'p') textOf(p)];
      expect(texts, <String>['Cover title', 'Cover subtitle paragraph.', '', 'Body heading', 'Body paragraph one.']);
      expect(documentXml(saved), contains('Cover subtitle paragraph.</w:t></w:r></w:p>$coverBreak'));
    });

    test('a new paragraph typed at the end of a section stays in that section', () {
      final file = Opened(docx(
        '<w:p><w:r><w:t>Cover title</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:pPr><w:r><w:t>Cover subtitle paragraph.</w:t></w:r></w:p>'
        '$bodyText',
      ));
      expect(file.delta.blocks.values.where((b) => b.kind == 'section'), hasLength(1));
      file.enterAfter('Cover subtitle paragraph.', 'Added at the end of the cover.');
      expect(sectioned(file.save()), <String>['Added at the end of the cover.']);
    });

    test('a paragraph split at the end of a section gives the break to its second half', () {
      final file = Opened(docx(
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:pPr><w:r><w:t>Cover subtitle paragraph.</w:t></w:r></w:p>'
        '$bodyText',
      ));
      file.doc.insert(file.at('paragraph.'), '\n');
      expect(sectioned(file.save()), <String>['paragraph.']);
    });

    test('deleting the break itself joins the two sections', () {
      final file = Opened(docx('$cover$coverBreak$bodyText'));
      final section = file.doc.toPlainText().indexOf('￼');
      file.doc.delete(section, 2);
      expect(sectioned(file.save()), isEmpty);
    });
  });

  group('lists', () {
    const numbered = '<w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
        '<w:lvlText w:val="%1."/></w:lvl><w:lvl w:ilvl="1"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1.%2."/></w:lvl></w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl></w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>';
    const styles = '<w:style w:type="paragraph" w:styleId="NumberedHeading"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:numPr><w:numId w:val="1"/></w:numPr><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="ListBullet"><w:name w:val="List Bullet"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:numPr><w:numId w:val="2"/></w:numPr><w:ind w:left="360" w:hanging="360"/></w:pPr></w:style>';

    String? numIdOf(XmlElement p) =>
        p.getElement('w:pPr')?.getElement('w:numPr')?.getElement('w:numId')?.getAttribute('w:val');

    test('a new numbered list starts one of its own, and numbered headings keep their numbers', () {
      final file = Opened(docx(
        '<w:p><w:pPr><w:pStyle w:val="NumberedHeading"/></w:pPr><w:r><w:t>Background</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Intro text paragraph.</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Second new item.</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="NumberedHeading"/></w:pPr><w:r><w:t>Methods</w:t></w:r></w:p>',
        styles: styles,
        numbering: numbered,
      ));
      final start = file.at('Intro text paragraph.');
      file.doc.format(start, 10, Attribute.ol);
      file.doc.format(file.at('Second new item.'), 5, Attribute.ol);
      final saved = file.save();
      final intro = numIdOf(paragraphWith(saved, 'Intro text'));
      expect(intro, isNot(anyOf('1', '2')));
      expect(numIdOf(paragraphWith(saved, 'Second new item.')), intro);
      expect(numIdOf(paragraphWith(saved, 'Background')), isNull);
      expect(numIdOf(paragraphWith(saved, 'Methods')), isNull);
      expect(documentXml(saved, 'word/numbering.xml'), contains('<w:num w:numId="$intro">'));
    });

    test('a list given by the paragraph style comes off with a number of 0', () {
      final file = Opened(docx(
        '<w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr><w:r><w:t>Bullet one</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr><w:r><w:t>Bullet two</w:t></w:r></w:p>',
        styles: styles,
        numbering: numbered,
      ));
      file.doc.format(file.at('Bullet two'), 3, Attribute.clone(Attribute.list, null));
      final saved = file.save();
      expect(numIdOf(paragraphWith(saved, 'Bullet two')), '0');
      final reread = Opened(saved);
      final line = reread.doc.queryChild(reread.at('Bullet two')).node!;
      expect(line.style.attributes[Attribute.list.key], isNull);
      expect(numIdOf(paragraphWith(saved, 'Bullet one')), isNull);
    });

    test('a numbered heading made normal text keeps the number the page shows', () {
      final file = Opened(docx(
        '<w:p><w:pPr><w:pStyle w:val="NumberedHeading"/></w:pPr><w:r><w:t>Methods</w:t></w:r></w:p>',
        styles: styles,
        numbering: numbered,
      ));
      file.doc.format(file.at('Methods'), 3, Attribute.clone(Attribute.header, null));
      final saved = file.save();
      final line = Opened(saved).doc.queryChild(0).node!;
      expect(line.style.attributes[Attribute.list.key]?.value, 'ordered');
      expect(line.style.attributes[Attribute.header.key], isNull);
    });
  });

  test('a long document edited in two far-apart places changes only those two paragraphs', () {
    final body = StringBuffer();
    for (var i = 0; i < 3000; i++) {
      final props = <String>[
        if (i % 11 == 0) '<w:pStyle w:val="Quote"/>',
        if (i % 5 == 0) '<w:spacing w:after="480"/>',
      ].join();
      body.write('<w:p>${props.isEmpty ? '' : '<w:pPr>$props</w:pPr>'}<w:r><w:t>Plain paragraph $i with ordinary words.</w:t></w:r></w:p>');
    }
    final bytes = docx(
      body.toString(),
      styles: '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:rPr><w:i/></w:rPr></w:style>',
    );
    final file = Opened(bytes);
    final second = file.at('Plain paragraph 1 with');
    file.doc.delete(second, 'Plain paragraph 1 with ordinary words.\n'.length);
    file.type('Plain paragraph 2900 with', 'EDITED ');
    final before = <String>[for (final p in bodyOf(bytes)) p.toXmlString()];
    final after = <String>[for (final p in bodyOf(file.save())) p.toXmlString()];
    expect(after.length, before.length - 1);
    var changed = 0;
    for (var i = 0, j = 0; i < before.length; i++) {
      if (i == 1) continue;
      if (before[i] != after[j]) changed++;
      j++;
    }
    expect(changed, 1);
  });

  test('a new paragraph after the subtitle takes after the words before the cursor, not the first run', () async {
    final file = Opened(await documentBytes(kHouseStyle));
    file.enterAfter('Fourth revision', 'Draft for review');
    final paragraph = paragraphWith(file.save(), 'Draft for review');
    final rPr = paragraph.descendantElements.firstWhere((e) => e.name.local == 'r').getElement('w:rPr');
    expect(rPr?.getElement('w:smallCaps'), isNull);
    expect(rPr?.getElement('w:color')?.getAttribute('w:val'), '5A6672');
  });

  test('a heading made normal text, and text typed after a heading, look in the file as they did on the page', () async {
    final file = Opened(await documentBytes(kHouseStyle));
    file.enterAfter('Setting the measure', 'A new paragraph under the heading.');
    final ops = file.doc.toDelta().toJson();
    final typed = ops.firstWhere((o) => (o['insert'] as String?)?.contains('A new paragraph') ?? false);
    expect(typed['attributes'], isNull);
    final line = file.doc.queryChild(file.at('A new paragraph')).node!;
    expect(line.style.attributes[Attribute.header.key], isNull);
    final saved = file.save();
    final reread = DocxDelta.read(saved);
    final again = reread.ops.firstWhere((o) => (o['insert'] as String?)?.contains('A new paragraph') ?? false);
    expect(again['attributes'], isNull);
    final paragraph = paragraphWith(saved, 'A new paragraph');
    expect(paragraph.getElement('w:pPr')?.getElement('w:pStyle')?.getAttribute('w:val'), 'BodyText');
  });
}
