import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/marks.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/seal.dart';
import 'package:quire/pdf/truetype.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/screens/edit/markup_screen.dart';

import 'support/pdf_bytes.dart';

/// A 300 by 400 page holding [annots], with [objects] after it as objects
/// 4 onwards.
Uint8List _pageWith(String annots, List<List<int>> objects, {String page = ''}) => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] $page /Annots [$annots] >>'),
      ...objects,
    ]);

List<int> _form(String bbox, String content, {String resources = ''}) => streamObj(
      '/Type /XObject /Subtype /Form /BBox [$bbox] /Resources << $resources >>',
      latin1.encode(content),
    );

const _helv = '/Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>';

List<Object?> _annots(PdfFile file) => (file.resolve(file.pages[0]['Annots']) as List?) ?? const <Object?>[];

Map<String, Object?> _annot(PdfFile file, int index) => file.dict(_annots(file)[index])!;

String _nameOf(PdfFile file, Object? raw) => latin1.decode((file.dict(raw)!['NM']! as PdfString).bytes);

List<double> _nums(PdfFile file, Object? raw) => [
      for (final v in file.resolve(raw)! as List) (file.resolve(v)! as num).toDouble(),
    ];

String _appearanceText(PdfFile file, Map<String, Object?> annot) {
  final normal = file.resolve(file.dict(annot['AP'])!['N']) as PdfStream;
  return latin1.decode(file.decodeStream(normal));
}

TrueTypeFont _inter() => TrueTypeFont.parse(File('assets/fonts/Inter-Regular.ttf').readAsBytesSync());

void main() {
  group('taking a comment off', () {
    Uint8List thread() => _pageWith('4 0 R 5 0 R 6 0 R 7 0 R 9 0 R 10 0 R 11 0 R', [
          obj('<< /Type /Annot /Subtype /Highlight /Rect [40 350 140 364] '
              '/QuadPoints [40 364 140 364 40 350 140 350] /NM (parent) /Popup 5 0 R /AP << /N 8 0 R >> >>'),
          obj('<< /Type /Annot /Subtype /Popup /Rect [150 300 250 360] /Parent 4 0 R /NM (parent-popup) >>'),
          obj('<< /Type /Annot /Subtype /Text /Rect [40 350 60 370] /IRT 4 0 R /NM (reply) /Contents (Reply) /Popup 7 0 R >>'),
          obj('<< /Type /Annot /Subtype /Popup /Rect [150 300 250 360] /Parent 6 0 R /NM (reply-popup) >>'),
          _form('40 350 140 364', '1 1 0 rg 40 350 100 14 re f'),
          obj('<< /Type /Annot /Subtype /Text /Rect [40 350 60 370] /IRT 4 0 R /NM (state) '
              '/State (Accepted) /StateModel (Review) >>'),
          obj('<< /Type /Annot /Subtype /Text /Rect [200 20 220 40] /NM (unrelated) >>'),
          obj('<< /Type /Annot /Subtype /Text /Rect [40 330 60 350] /IRT 6 0 R /NM (reply-to-reply) >>'),
        ]);

    test('takes its replies, its review states and every note window with it', () {
      final out = PdfAnnotator.apply(PdfFile.open(thread()), updates: const [MarkRemoved(MarkOrigin(0, 0))]);
      final file = PdfFile.open(out);
      expect([for (final a in _annots(file)) _nameOf(file, a)], ['unrelated']);
    });

    test('the editor knows the same annotations go with it', () {
      expect(markThread(PdfFile.open(thread()), 0, 0), {0, 1, 2, 3, 4, 6});
    });

    test('taking a reply off leaves the comment it answers', () {
      final out = PdfAnnotator.apply(PdfFile.open(thread()), updates: const [MarkRemoved(MarkOrigin(0, 2))]);
      final file = PdfFile.open(out);
      expect([for (final a in _annots(file)) _nameOf(file, a)], ['parent', 'parent-popup', 'state', 'unrelated']);
    });

    test('the first of a group takes the group with it', () {
      final bytes = _pageWith('4 0 R 5 0 R', [
        obj('<< /Type /Annot /Subtype /Square /Rect [20 20 120 80] /NM (square) /AP << /N 6 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Circle /Rect [140 20 240 80] /NM (circle) /IRT 4 0 R /RT /Group /AP << /N 7 0 R >> >>'),
        _form('20 20 120 80', '0 0 1 RG 20 20 100 60 re S'),
        _form('140 20 240 80', '0 0 1 RG 140 20 100 60 re S'),
      ]);
      final out = PdfAnnotator.apply(PdfFile.open(bytes), updates: const [MarkRemoved(MarkOrigin(0, 0))]);
      expect(_annots(PdfFile.open(out)), isEmpty);
    });
  });

  group('words in a comment', () {
    test('a text string with no byte order mark is read as PDFDocEncoding', () {
      final words = pdfTextString(PdfString(Uint8List.fromList([
        0x49, 0x74, 0x90, 0x73, 0x20, 0x84, 0x20, 0x8D, 0x71, 0x8E, 0x20, 0x80, 0x20, //
        0x63, 0x61, 0x66, 0xE9, 0x20, 0xA0, 0x35,
      ])));
      expect(words, 'It’s \u2014 “q” • café €5');
    });

    test('a comment in PDFDocEncoding is read whole and moved without being rewritten', () {
      final bytes = _pageWith('4 0 R', [
        obj(r'<< /Type /Annot /Subtype /FreeText /Rect [20 330 280 380] /DA (/Helv 12 Tf 0 0 1 rg) '
            r'/Contents (It\220s \204 caf\351 \2405) >>'),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      expect((found.edit as TextBoxEdit).text, 'It’s \u2014 café €5');
      final changes = changesFor([EditorMark(id: 1, edit: found.edit, found: found).movedBy(const Offset(0, 50))], const []);
      expect(changes.updates.single, isA<MarkMoved>());
      final again = PdfFile.open(PdfAnnotator.apply(file, updates: changes.updates));
      final after = _annot(again, 0);
      expect((after['Contents']! as PdfString).bytes, (_annot(file, 0)['Contents']! as PdfString).bytes);
      expect(after.containsKey('AP'), isFalse);
    });

    test('words Helvetica cannot set are written in the app typeface and read back whole', () {
      const words = 'Zażółć gęślą jaźń. Привет, мир. Ελληνικά';
      final plain = _pageWith('', const []);
      final out = PdfAnnotator.annotated(
        PdfFile.open(plain),
        [const TextBoxEdit(0, rect: Rect.fromLTWH(20, 40, 260, 80), text: words, size: 12)],
        font: _inter(),
      );
      final file = PdfFile.open(out);
      final text = ContentInterpreter(file).run(file.pages[0]).texts.map((t) => t.text).join();
      for (final word in ['Zażółć', 'gęślą', 'jaźń', 'Привет', 'мир', 'Ελληνικά']) {
        expect(text, contains(word), reason: word);
      }
      expect(text, isNot(contains('?')));
      final font = file.dict(file.dict(file.dict(file.dict(_annot(file, 0)['AP'])!['N'])!['Resources'])!['Font'])!;
      final type0 = file.dict(font['QuireWords'])!;
      expect((type0['Subtype']! as PdfName).value, 'Type0');
      // Only the letters used go in, not the whole typeface.
      expect(out.length - plain.length, lessThan(80000));
    });

    test('words the typeface cannot set either are written as the picture the editor made', () {
      final out = PdfAnnotator.annotated(
        PdfFile.open(_pageWith('', const [])),
        [
          TextBoxEdit(
            0,
            rect: const Rect.fromLTWH(20, 40, 100, 20),
            text: '你好',
            drawn: PdfImage(width: 2, height: 1, rgb: Uint8List.fromList([0, 0, 0, 0, 0, 0])),
          ),
        ],
        font: _inter(),
      );
      final file = PdfFile.open(out);
      final list = ContentInterpreter(file).run(file.pages[0]);
      expect(list.images, isNotEmpty);
      expect(list.texts.where((t) => t.text.contains('?')), isEmpty);
    });

    test('which way words are written', () {
      final font = _inter();
      // New words are set in the app's own face, as the editor draws them.
      expect(PdfAnnotator.wordsFace('Plain café \u2014 “quoted”', font), WordsFace.embedded);
      expect(PdfAnnotator.wordsFace('Plain café \u2014 “quoted”', null), WordsFace.standard);
      // Another program's box keeps its standard face while it can.
      expect(PdfAnnotator.wordsFace('Plain café', font, family: 'Courier'), WordsFace.standard);
      expect(PdfAnnotator.wordsFace('Zażółć', font, family: 'Courier'), WordsFace.embedded);
      expect(PdfAnnotator.wordsFace('Zażółć', font), WordsFace.embedded);
      expect(PdfAnnotator.wordsFace('Zażółć', null), WordsFace.drawn);
      expect(PdfAnnotator.wordsFace('你好', font), WordsFace.drawn);
      expect(PdfAnnotator.wordsFace('שלום', font), WordsFace.drawn);
      expect(PdfAnnotator.wordsFace('é', font), WordsFace.drawn);
    });
  });

  group('recolouring a box of words another program drew', () {
    test('a callout keeps its line, its inner box and its arrow, and the words stay inside', () {
      final bytes = _pageWith('4 0 R', [
        obj('<< /Type /Annot /Subtype /FreeText /IT /FreeTextCallout /Rect [20 200 280 300] '
            '/CL [30 210 80 270 120 270] /RD [100 0 0 50] /LE /OpenArrow '
            '/DA (/Helv 12 Tf 0 0 1 rg) /Contents (See this figure) /AP << /N 5 0 R >> >>'),
        _form(
          '20 200 280 300',
          '0 0 0 RG 1 w 30 210 m 80 270 l 120 270 l S 120 250 160 50 re S '
              'BT /Helv 12 Tf 0 0 1 rg 124 284 Td (See this figure) Tj ET',
          resources: _helv,
        ),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      final words = found.edit as TextBoxEdit;
      expect(words.inset.left, closeTo(102, 0.01));
      expect(words.inset.bottom, closeTo(52, 0.01));
      final again = PdfFile.open(PdfAnnotator.apply(file, updates: [
        MarkRewritten(found.origin, words.copyWith(color: 0xFFD23B3B)),
      ]));
      final dict = _annot(again, 0);
      expect((dict['IT']! as PdfName).value, 'FreeTextCallout');
      expect((dict['LE']! as PdfName).value, 'OpenArrow');
      expect(_nums(again, dict['CL']), [30, 210, 80, 270, 120, 270]);
      expect(_nums(again, dict['RD']), [100, 0, 0, 50]);
      final drawing = _appearanceText(again, dict);
      expect(drawing, contains('30 210 m 80 270 l 120 270 l S'));
      expect(drawing, contains('120 250 160 50 re S'));
      final texts = ContentInterpreter(again).run(again.pages[0]).texts;
      expect(texts.map((t) => t.text).join(), 'See this figure');
      // Inside the inner box, which starts 120 across and ends 50 up from
      // the bottom of the page's 200.
      expect(texts.first.x, greaterThanOrEqualTo(120 - 0.01));
      expect(texts.first.y, lessThanOrEqualTo(400 - 250 + 0.01));
    });

    test('a bordered and filled box keeps its border and fill', () {
      final bytes = _pageWith('4 0 R', [
        obj('<< /Type /Annot /Subtype /FreeText /Rect [40 280 240 340] /BS << /W 2 >> /C [1 0 0] /IC [1 1 0.7] '
            '/DA (/Helv 12 Tf 0 g) /Contents (Boxed) /AP << /N 5 0 R >> >>'),
        _form(
          '40 280 240 340',
          '1 1 0.7 rg 41 281 198 58 re f 1 0 0 RG 2 w 41 281 198 58 re S BT /Helv 12 Tf 0 g 46 322 Td (Boxed) Tj ET',
          resources: _helv,
        ),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      final again = PdfFile.open(PdfAnnotator.apply(file, updates: [
        MarkRewritten(found.origin, (found.edit as TextBoxEdit).copyWith(color: 0xFF1F4FD8)),
      ]));
      final dict = _annot(again, 0);
      expect(_nums(again, dict['C']), [1, 0, 0]);
      expect(_nums(again, dict['IC']), [1, 1, 0.7]);
      expect((file.dict(dict['BS'])!['W']! as num).toDouble(), 2);
      final drawing = _appearanceText(again, dict);
      expect(drawing, contains('1 1 0.7 rg 41 281 198 58 re f'));
      expect(drawing, contains('1 0 0 RG 2 w 41 281 198 58 re S'));
      expect(latin1.decode((dict['DA']! as PdfString).bytes), '/Helv 12 Tf 0.1216 0.3098 0.8471 rg');
    });
  });

  test('sizes on a /UserUnit page are read and written in its own units', () {
    final bytes = _pageWith(
      '4 0 R 5 0 R',
      [
        obj('<< /Type /Annot /Subtype /FreeText /Rect [20 300 220 340] /DA (/Helv 12 Tf 0 0 1 rg) '
            '/Contents (Twelve) /AP << /N 6 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Ink /Rect [27 107 213 193] /InkList [[30 110 210 190]] /BS << /W 3 >> '
            '/C [0 0 1] /AP << /N 7 0 R >> >>'),
        _form('20 300 220 340', 'BT /Helv 12 Tf 24 324 Td (Twelve) Tj ET', resources: _helv),
        _form('27 107 213 193', '0 0 1 RG 3 w 30 110 m 210 190 l S'),
      ],
      page: '/UserUnit 2',
    );
    final file = PdfFile.open(bytes);
    final found = readMarks(file, 0);
    final words = found[0].edit as TextBoxEdit;
    final ink = found[1].edit as InkEdit;
    expect(words.size, 24);
    expect(ink.width, 6);
    final again = PdfFile.open(PdfAnnotator.apply(file, updates: [
      MarkRewritten(found[0].origin, words.copyWith(color: 0xFFD23B3B)),
      MarkRewritten(found[1].origin, ink.copyWith(color: 0xFFD23B3B)),
    ]));
    expect(latin1.decode((_annot(again, 0)['DA']! as PdfString).bytes), startsWith('/Helv 12 Tf'));
    expect((again.dict(_annot(again, 1)['BS'])!['W']! as num).toDouble(), 3);
    final reread = readMarks(again, 0);
    expect((reread[0].edit as TextBoxEdit).size, 24);
    expect((reread[1].edit as InkEdit).width, 6);
  });

  test('a comment with no appearance of its own is moved, keeping its style, colours and rich text', () {
    final bytes = _pageWith('4 0 R', [
      obj('<< /Type /Annot /Subtype /FreeText /Rect [40 300 240 340] /DA (0 0 1 rg) '
          '/DS (font: normal normal 14pt Helvetica;text-align:left;color:#0000ff) /C [1 1 0.8] '
          '/RC (<body><p>Size fourteen</p></body>) /Contents (Size fourteen) >>'),
    ]);
    final file = PdfFile.open(bytes);
    final found = readMarks(file, 0).single;
    final words = found.edit as TextBoxEdit;
    expect(found.hasLook, isFalse);
    expect(words.size, 14);
    expect(words.color, 0xFF0000FF);
    final changes = changesFor([EditorMark(id: 1, edit: words, found: found).movedBy(const Offset(0, 30))], const []);
    expect(changes.updates.single, isA<MarkMoved>());
    final again = PdfFile.open(PdfAnnotator.apply(file, updates: changes.updates));
    final dict = _annot(again, 0);
    for (final key in ['DS', 'RC', 'DA']) {
      expect((dict[key]! as PdfString).bytes, (_annot(file, 0)[key]! as PdfString).bytes, reason: key);
    }
    expect(_nums(again, dict['C']), [1, 1, 0.8]);
    expect(_nums(again, dict['Rect']), [40, 270, 240, 310]);
    expect(dict.containsKey('AP'), isFalse);
  });

  test('a locked mark is left alone, and words locked against change still move as they look', () {
    final bytes = _pageWith('4 0 R 5 0 R', [
      obj('<< /Type /Annot /Subtype /Stamp /F 132 /Rect [100 100 200 150] /AP << /N 6 0 R >> >>'),
      obj('<< /Type /Annot /Subtype /FreeText /F 516 /Rect [20 300 220 340] /DA (/Helv 12 Tf 0 g) '
          '/Contents (Fixed words) /AP << /N 7 0 R >> >>'),
      _form('100 100 200 150', '1 0 0 rg 100 100 100 50 re f'),
      _form('20 300 220 340', 'BT /Helv 12 Tf 24 324 Td (Fixed words) Tj ET', resources: _helv),
    ]);
    final found = readMarks(PdfFile.open(bytes), 0);
    expect(found, hasLength(1));
    expect(found.single.origin, const MarkOrigin(0, 1));
    expect(found.single.edit, isA<KeptEdit>());
  });

  group('round three', () {
    test('a text box whose lines break with CR is read as lines and written as text', () {
      final bytes = _pageWith('4 0 R', [
        obj(r'<< /Type /Annot /Subtype /FreeText /Rect [40 280 260 340] /DA (/Helv 12 Tf 0 0 1 rg) '
            r'/Contents (Check clause 4\rand the rent date) /AP << /N 5 0 R >> >>'),
        _form('40 280 260 340', 'BT /Helv 12 Tf 44 324 Td (Check clause 4) Tj 0 -14 Td (and the rent date) Tj ET',
            resources: _helv),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      final words = found.edit as TextBoxEdit;
      expect(words.text, 'Check clause 4\nand the rent date');
      expect(PdfAnnotator.wordsFace(words.text, _inter()), isNot(WordsFace.drawn));
      final again = PdfFile.open(PdfAnnotator.apply(file,
          updates: [MarkRewritten(found.origin, words.copyWith(color: 0xFFD23B3B))], font: _inter()));
      final drawing = _appearanceText(again, _annot(again, 0));
      expect(drawing, isNot(contains(kDrawnWords)));
      final texts = ContentInterpreter(again).run(again.pages[0]).texts;
      expect(texts.map((t) => t.y).toSet(), hasLength(2));
      // The words were not changed, so what the file says of them stays.
      expect((_annot(again, 0)['Contents']! as PdfString).bytes, (_annot(file, 0)['Contents']! as PdfString).bytes);
    });

    test('words saved as a picture are replaced, not kept under the new ones', () {
      final first = PdfAnnotator.annotated(
        PdfFile.open(_pageWith('', const [])),
        [
          TextBoxEdit(
            0,
            rect: const Rect.fromLTWH(40, 60, 200, 40),
            text: 'שלום עולם',
            size: 18,
            drawn: PdfImage(width: 2, height: 1, rgb: Uint8List.fromList([0, 0, 0, 0, 0, 0])),
          ),
        ],
        font: _inter(),
      );
      final file = PdfFile.open(first);
      final found = readMarks(file, 0).single;
      final again = PdfFile.open(PdfAnnotator.apply(file,
          updates: [MarkRewritten(found.origin, (found.edit as TextBoxEdit).copyWith(text: 'Hello'))], font: _inter()));
      final dict = _annot(again, 0);
      expect(_appearanceText(again, dict), isNot(contains(kDrawnWords)));
      final look = again.dict(again.dict(dict['AP'])!['N'])!;
      final pictures = again.dict(again.dict(look['Resources'])!['XObject']);
      expect(pictures?.containsKey(kDrawnWords) ?? false, isFalse);
      expect(ContentInterpreter(again).run(again.pages[0]).images, isEmpty);
    });

    test('a mark copied onto a page turned another way is drawn upright, as the editor showed it', () {
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Annots [5 0 R] >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Rotate 90 >>'),
        obj('<< /Type /Annot /Subtype /Stamp /Rect [50 300 250 360] /AP << /N 6 0 R >> >>'),
        _form('50 300 250 360', '1 0 0 rg 50 300 200 60 re f'),
      ]);
      final file = PdfFile.open(bytes);
      final stamp = readMarks(file, 0).single;
      expect(stamp.edit.bounds.width, closeTo(200, 0.01));
      final out = PdfFile.open(PdfAnnotator.apply(file, added: [
        KeptEdit(1, rect: const Rect.fromLTWH(100, 80, 200, 60), origin: stamp.origin),
      ]));
      final paths = ContentInterpreter(out).run(out.pages[1]).paths;
      expect(paths, isNotEmpty);
      var l = double.infinity, t = double.infinity, r = double.negativeInfinity, b = double.negativeInfinity;
      for (final path in paths) {
        for (final seg in path.segs) {
          for (var i = 0; i + 1 < seg.pts.length; i += 2) {
            l = math.min(l, seg.pts[i]);
            r = math.max(r, seg.pts[i]);
            t = math.min(t, seg.pts[i + 1]);
            b = math.max(b, seg.pts[i + 1]);
          }
        }
      }
      expect(r - l, closeTo(200, 0.5));
      expect(b - t, closeTo(60, 0.5));
      expect(l, closeTo(100, 0.5));
      expect(t, closeTo(80, 0.5));
    });

    test('recolouring keeps opacity, dashes and the highlight\'s own opacity', () {
      final bytes = _pageWith('4 0 R 5 0 R', [
        obj('<< /Type /Annot /Subtype /Ink /Rect [20 20 200 100] /InkList [[30 30 190 90]] /C [1 0.8 0] /CA 0.5 '
            '/BS << /W 3 /S /D /D [6 4] >> /AP << /N 6 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Highlight /Rect [40 350 140 364] /QuadPoints [40 364 140 364 40 350 140 350] '
            '/C [1 1 0] /CA 1 /AP << /N 7 0 R >> >>'),
        _form('20 20 200 100', '/GS0 gs 1 0.8 0 RG 3 w [6 4] 0 d 30 30 m 190 90 l S',
            resources: '/ExtGState << /GS0 << /CA 0.5 /ca 0.5 >> >>'),
        _form('40 350 140 364', '/GS0 gs 1 1 0 rg 40 350 100 14 re f', resources: '/ExtGState << /GS0 << /BM /Multiply >> >>'),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0);
      final ink = found[0].edit as InkEdit;
      final lit = found[1].edit as HighlightEdit;
      expect(ink.opacity, 0.5);
      expect(lit.opacity, 1);
      final again = PdfFile.open(PdfAnnotator.apply(file, updates: [
        MarkRewritten(found[0].origin, ink.copyWith(color: 0xFF1F4FD8)),
        MarkRewritten(found[1].origin, lit.copyWith(color: 0xFF8BE28B)),
      ]));
      final inkDict = _annot(again, 0);
      expect((inkDict['CA']! as num).toDouble(), 0.5);
      final style = again.dict(inkDict['BS'])!;
      expect((style['S']! as PdfName).value, 'D');
      expect(_nums(again, style['D']), [6, 4]);
      expect(_appearanceText(again, inkDict), contains('[6 4] 0 d'));
      final litDict = _annot(again, 1);
      expect(litDict.containsKey('CA'), isFalse);
      final gs = again.dict(again.dict(again.dict(again.dict(litDict['AP'])!['N'])!['Resources'])!['ExtGState'])!['Mark']!;
      expect((again.dict(gs)!['BM']! as PdfName).value, 'Multiply');
      expect((again.dict(gs)!['ca']! as num).toDouble(), 1);
    });

    test('a box of words keeps its typeface when it is recoloured', () {
      final bytes = _pageWith('4 0 R', [
        obj('<< /Type /Annot /Subtype /FreeText /IT /FreeTextTypewriter /Rect [40 300 240 330] '
            '/DA (/Cour 14 Tf 0 0 0 rg) /Contents (Received 12 May) /AP << /N 5 0 R >> >>'),
        _form('40 300 240 330', 'BT /Cour 14 Tf 0 g 42 310 Td (Received 12 May) Tj ET',
            resources: '/Font << /Cour << /Type /Font /Subtype /Type1 /BaseFont /Courier >> >>'),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      final words = found.edit as TextBoxEdit;
      expect(words.family, 'Courier');
      final again = PdfFile.open(PdfAnnotator.apply(file,
          updates: [MarkRewritten(found.origin, words.copyWith(color: 0xFFD23B3B))], font: _inter()));
      final dict = _annot(again, 0);
      expect(latin1.decode((dict['DA']! as PdfString).bytes), startsWith('/Cour 14 Tf'));
      final look = again.dict(again.dict(dict['AP'])!['N'])!;
      final fonts = again.dict(again.dict(look['Resources'])!['Font'])!;
      final used = again.dict(fonts['QuireHelv'])!;
      expect((used['BaseFont']! as PdfName).value, 'Courier');
    });

    test('a copy of another program\'s callout keeps its line, arrow and frame', () {
      final bytes = _pageWith('4 0 R', [
        obj('<< /Type /Annot /Subtype /FreeText /IT /FreeTextCallout /Rect [20 200 280 300] '
            '/CL [30 210 80 270 120 270] /RD [100 0 0 50] /LE /OpenArrow /C [1 1 0.6] '
            '/DA (/Helv 12 Tf 0 0 1 rg) /Contents (See this figure) /AP << /N 5 0 R >> >>'),
        _form('20 200 280 300', '0 0 0 RG 1 w 30 210 m 80 270 l 120 270 l S 120 250 160 50 re S '
            'BT /Helv 12 Tf 0 0 1 rg 124 284 Td (See this figure) Tj ET', resources: _helv),
      ]);
      final file = PdfFile.open(bytes);
      final found = readMarks(file, 0).single;
      final copy = KeptEdit(0, rect: found.edit.bounds.shift(const Offset(10, 20)), origin: found.origin);
      final again = PdfFile.open(PdfAnnotator.apply(file, added: [copy]));
      final dict = _annot(again, 1);
      expect((dict['IT']! as PdfName).value, 'FreeTextCallout');
      expect((dict['LE']! as PdfName).value, 'OpenArrow');
      // Moved 10 across and 20 down the page, which is 20 down in user space.
      expect(_nums(again, dict['CL']), [40, 190, 90, 250, 130, 250]);
      expect(_nums(again, dict['C']), [1, 1, 0.6]);
      expect(dict.containsKey('NM'), isTrue);
      expect(latin1.decode((dict['NM']! as PdfString).bytes), startsWith('quire-'));
    });

    test('a file that does not allow comments is not changed, unless opened by its owner', () {
      final plain = PdfAnnotator.annotated(PdfFile.open(_pageWith('', const [])), [
        const TextBoxEdit(0, rect: Rect.fromLTWH(40, 60, 200, 40), text: 'A note'),
      ]);
      final sealed = sealedPdf(plain, 'reader', ownerPassword: 'keeper', permissions: -4 & ~32);
      final reader = PdfFile.open(sealed, password: 'reader');
      expect(PdfAnnotator.allowsComments(reader), isFalse);
      expect(
        () => PdfAnnotator.apply(reader, updates: const [MarkRemoved(MarkOrigin(0, 0))]),
        throwsA(isA<PdfWriteError>()),
      );
      final keeper = PdfFile.open(sealed, password: 'keeper');
      expect(PdfAnnotator.allowsComments(keeper), isTrue);
      final certified = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R /Perms << /DocMDP 4 0 R >> >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] >>'),
        obj('<< /Type /Sig /Reference [<< /Type /SigRef /TransformMethod /DocMDP /TransformParams << /P 1 >> >>] >>'),
      ]);
      expect(PdfAnnotator.allowsComments(PdfFile.open(certified)), isFalse);
    });

    test('a read-only mark is left alone, and other programs\' lines, notes and underlines are offered', () {
      final bytes = _pageWith('4 0 R 5 0 R 6 0 R 7 0 R 8 0 R', [
        obj('<< /Type /Annot /Subtype /Stamp /F 68 /Rect [100 100 200 150] /AP << /N 9 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Underline /Rect [40 330 140 344] /QuadPoints [40 344 140 344 40 330 140 330] /AP << /N 9 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Line /Rect [55 195 205 255] /L [60 250 200 200] /AP << /N 9 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Text /Rect [250 290 270 310] /AP << /N 9 0 R >> >>'),
        obj('<< /Type /Annot /Subtype /Square /Rect [30 310 250 378] /C [1 0 0] /AP << /N 9 0 R >> >>'),
        _form('0 0 300 400', '0 g 0 0 1 1 re f'),
      ]);
      final found = readMarks(PdfFile.open(bytes), 0);
      expect(found.map((f) => f.subtype), ['Underline', 'Line', 'Text', 'Square']);
      expect(found[0].movable, isFalse);
      expect(found[1].outline, isNotNull);
      expect(found[2].resizable, isFalse);
      expect(found[2].movable, isTrue);
      expect(found[3].outline, isNotNull);
    });
  });

  test('text objects come out of a drawing and nothing else does', () {
    final out = contentWithoutText(Uint8List.fromList(latin1.encode(
      'q 1 0 0 RG 0 0 10 10 re S BT /F1 12 Tf (a (nested) ET) Tj ET 5 5 m 6 6 l S '
      'BI /W 1 /H 1 /BPC 8 /CS /G ID \x00BT\x00 EI Q',
    )));
    expect(
      latin1.decode(out),
      'q 1 0 0 RG 0 0 10 10 re S  5 5 m 6 6 l S BI /W 1 /H 1 /BPC 8 /CS /G ID \x00BT\x00 EI Q',
    );
  });
}
