import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/seal.dart';
import 'package:quire/pdf/writer.dart';

import 'support/fixtures.dart';
import 'support/pdf_bytes.dart';

/// A page 200 wide and 300 tall, turned by [rotate].
Uint8List _page({int rotate = 0}) => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
          '/Rotate $rotate /Contents 4 0 R >>'),
      streamObj('', ascii.encode('0 g 0 0 1 1 re f')),
    ]);

PageDisplayList _run(Uint8List bytes, {String password = ''}) {
  final file = PdfFile.open(bytes, password: password);
  return ContentInterpreter(file).run(file.pages[0]);
}

/// The box a path's points span, in the reader's points.
Rect _span(PathCmd path) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final seg in path.segs) {
    for (var i = 0; i + 1 < seg.pts.length; i += 2) {
      final x = seg.pts[i], y = seg.pts[i + 1];
      if (x < l) l = x;
      if (x > r) r = x;
      if (y < t) t = y;
      if (y > b) b = y;
    }
  }
  return Rect.fromLTRB(l, t, r, b);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edits are added after the file, which is left as it was', () async {
    final original = await documentBytes(kPressLease);
    final out = PdfAnnotator.annotated(PdfFile.open(original), [
      const HighlightEdit(0, rects: [Rect.fromLTWH(60, 100, 200, 14)]),
    ]);
    expect(out.length, greaterThan(original.length));
    expect(out.sublist(0, original.length), original);
  });

  test('every edit is an annotation of its own kind with its own look', () async {
    final original = await documentBytes(kPressLease);
    final file = PdfFile.open(original);
    final had = (file.resolve(file.pages[0]['Annots']) as List?)?.length ?? 0;
    final out = PdfAnnotator.annotated(file, [
      const TextBoxEdit(0, rect: Rect.fromLTWH(60, 60, 220, 40), text: 'Checked by quire'),
      const InkEdit(0, strokes: [[Offset(60, 200), Offset(120, 220), Offset(180, 200)]]),
      const HighlightEdit(0, rects: [Rect.fromLTWH(60, 300, 200, 14)]),
      const StrikeEdit(0, rects: [Rect.fromLTWH(60, 330, 200, 14)]),
      ImageEdit(
        0,
        rect: const Rect.fromLTWH(300, 500, 40, 20),
        image: PdfImage(width: 2, height: 1, rgb: Uint8List.fromList([255, 0, 0, 0, 0, 255])),
      ),
    ]);
    final again = PdfFile.open(out);
    final annots = (again.resolve(again.pages[0]['Annots'])! as List)
        .map(again.dict)
        .toList();
    expect(annots, hasLength(had + 5));
    final kinds = annots.skip(had).map((a) => (a!['Subtype']! as PdfName).value);
    expect(kinds, ['FreeText', 'Ink', 'Highlight', 'StrikeOut', 'Stamp']);
    for (final annot in annots.skip(had)) {
      expect(again.resolve(again.dict(annot!['AP'])!['N']), isA<PdfStream>());
    }
  });

  test('quire draws what it added: the words, the ink and the picture', () async {
    final original = await documentBytes(kPressLease);
    final before = _run(original);
    final out = PdfAnnotator.annotated(PdfFile.open(original), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(60, 60, 220, 40), text: 'Checked by quire'),
      const InkEdit(0, strokes: [[Offset(60, 200), Offset(120, 220)]]),
      ImageEdit(
        0,
        rect: const Rect.fromLTWH(300, 500, 40, 20),
        image: PdfImage(width: 1, height: 1, rgb: Uint8List.fromList([9, 9, 9])),
      ),
    ]);
    final after = _run(out);
    expect(after.texts.map((t) => t.text), contains('Checked by quire'));
    expect(after.paths.length, greaterThan(before.paths.length));
    expect(after.images.length, before.images.length + 1);
    final placed = after.texts.firstWhere((t) => t.text == 'Checked by quire');
    expect(placed.x, closeTo(60, 0.5));
    expect(placed.y, closeTo(72, 0.5));
  });

  for (final rotate in [0, 90, 180, 270]) {
    test('a mark lands where it was put on a page turned $rotate', () {
      const where = Rect.fromLTWH(30, 40, 50, 12);
      final out = PdfAnnotator.annotated(PdfFile.open(_page(rotate: rotate)), [
        const HighlightEdit(0, rects: [where]),
      ]);
      final list = _run(out);
      final drawn = _span(list.paths.last);
      expect(drawn.left, closeTo(where.left, 0.01));
      expect(drawn.top, closeTo(where.top, 0.01));
      expect(drawn.right, closeTo(where.right, 0.01));
      expect(drawn.bottom, closeTo(where.bottom, 0.01));
    });
  }

  test('a long line is wrapped inside its box', () {
    final out = PdfAnnotator.annotated(PdfFile.open(_page()), [
      const TextBoxEdit(
        0,
        rect: Rect.fromLTWH(10, 10, 80, 200),
        text: 'a sentence long enough that it cannot fit on one line',
        size: 10,
      ),
    ]);
    final lines = _run(out).texts;
    expect(lines.length, greaterThan(2));
    for (final line in lines) {
      expect(line.x + line.widthPts, lessThanOrEqualTo(90.5));
    }
  });

  test('an edit goes into a sealed file under its own key', () {
    final sealed = sealedPdf(_page(), 'secret');
    final out = PdfAnnotator.annotated(PdfFile.open(sealed, password: 'secret'), [
      const TextBoxEdit(0, rect: Rect.fromLTWH(10, 10, 150, 30), text: 'Sealed note'),
    ]);
    expect(() => PdfFile.open(out), throwsA(isA<PdfLocked>()));
    expect(
      _run(out, password: 'secret').texts.map((t) => t.text),
      contains('Sealed note'),
    );
  });

  test('a hidden annotation is not drawn', () {
    final bytes = buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
          '/Annots [5 0 R 6 0 R] >>'),
      streamObj('/Type /XObject /Subtype /Form /BBox [0 0 10 10]',
          ascii.encode('0 0 10 10 re f')),
      obj('<< /Type /Annot /Subtype /Square /Rect [0 0 10 10] /AP << /N 4 0 R >> >>'),
      obj('<< /Type /Annot /Subtype /Square /Rect [20 20 30 30] /F 2 /AP << /N 4 0 R >> >>'),
    ]);
    expect(_run(bytes).paths, hasLength(1));
  });

  test('nothing to add is the file that was read', () async {
    final original = await documentBytes(kPressLease);
    expect(PdfAnnotator.annotated(PdfFile.open(original), const []), same(original));
  });
}
