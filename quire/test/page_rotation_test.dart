import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/writer.dart';

import 'sign_test.dart' show scriptStrokes;

/// A one page PDF, 612 by 792, turned by [rotate], carrying one filled square
/// 72 points wide whose bottom left corner is 100 points right of the page's
/// left edge and 200 points up from its foot.
Uint8List _page({required int rotate}) {
  const content = '0 0 0 rg\n100 200 72 72 re\nf\n';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate $rotate '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length ${content.length} >>\nstream\n${content}endstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(latin1.encode(out.toString()));
}

PageDisplayList _listOf(Uint8List bytes) {
  final file = PdfFile.open(bytes);
  return ContentInterpreter(file).run(file.pages.first);
}

/// Where a painted shape sits on the page as the reader draws it.
Rect _boundsOf(PageDisplayList list, {int? color}) {
  var left = double.infinity;
  var top = double.infinity;
  var right = -double.infinity;
  var bottom = -double.infinity;
  for (final path in list.paths) {
    if (!path.fill) continue;
    if (color != null && path.fillColor != color) continue;
    for (final seg in path.segs) {
      for (var i = 0; i + 1 < seg.pts.length; i += 2) {
        final x = seg.pts[i];
        final y = seg.pts[i + 1];
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

void _closeToRect(Rect was, Rect wanted) {
  expect(was.left, closeTo(wanted.left, 0.5));
  expect(was.top, closeTo(wanted.top, 0.5));
  expect(was.right, closeTo(wanted.right, 0.5));
  expect(was.bottom, closeTo(wanted.bottom, 0.5));
}

void main() {
  group('a page the file says is turned', () {
    test('is as wide as it is tall, the other way about', () {
      expect(_listOf(_page(rotate: 0)).widthPts, 612);
      expect(_listOf(_page(rotate: 0)).heightPts, 792);
      final sideways = _listOf(_page(rotate: 90));
      expect(sideways.widthPts, 792);
      expect(sideways.heightPts, 612);
      expect(sideways.rotation, 90);
      final other = _listOf(_page(rotate: 270));
      expect(other.widthPts, 792);
      expect(other.heightPts, 612);
    });

    test('is drawn turned, so what was on its side stands up', () {
      // Upright, the square is 100 from the left and 792 - 272 from the top.
      _closeToRect(
        _boundsOf(_listOf(_page(rotate: 0))),
        const Rect.fromLTRB(100, 520, 172, 592),
      );
      // A quarter turn clockwise puts the left edge at the top.
      _closeToRect(
        _boundsOf(_listOf(_page(rotate: 90))),
        const Rect.fromLTRB(200, 100, 272, 172),
      );
      _closeToRect(
        _boundsOf(_listOf(_page(rotate: 180))),
        const Rect.fromLTRB(440, 200, 512, 272),
      );
      _closeToRect(
        _boundsOf(_listOf(_page(rotate: 270))),
        const Rect.fromLTRB(520, 440, 592, 512),
      );
    });

    test('a turn that is not a quarter is no turn at all', () {
      final list = _listOf(_page(rotate: 45));
      expect(list.rotation, 0);
      expect(list.widthPts, 612);
    });
  });

  group('a signature set into a turned page', () {
    for (final rotate in <int>[0, 90, 180, 270]) {
      test('lands where it was placed, with /Rotate $rotate', () {
        final bytes = _page(rotate: rotate);
        final file = PdfFile.open(bytes);
        const where = Rect.fromLTWH(120, 60, 200, 80);
        final signed = PdfSignatureWriter.signed(file, <PlacedInk>[
          PlacedInk(
            pageIndex: 0,
            rect: where,
            outlines: SignatureMark.of(scriptStrokes()).outlines,
          ),
        ]);

        // Read back through the same reader the page is drawn with: the ink
        // has to come out where the reader put it, whatever the turn.
        final ink = _boundsOf(_listOf(signed), color: 0xFF111111);
        expect(ink.left, greaterThanOrEqualTo(where.left - 1));
        expect(ink.top, greaterThanOrEqualTo(where.top - 1));
        expect(ink.right, lessThanOrEqualTo(where.right + 1));
        expect(ink.bottom, lessThanOrEqualTo(where.bottom + 1));
        // And it fills the box it was given rather than sitting in a corner
        // of it.
        expect(ink.width, greaterThan(where.width * 0.8));
        expect(ink.height, greaterThan(where.height * 0.5));
      });
    }
  });
}
