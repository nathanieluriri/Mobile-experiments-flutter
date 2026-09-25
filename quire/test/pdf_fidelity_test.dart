import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/shading.dart';

import 'support/pdf_bytes.dart';

/// A 200 point square page drawing [content] with [resources].
PdfFile _page(String content, {String resources = ''}) =>
    PdfFile.open(buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << $resources >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode(content)),
    ]));

PageDisplayList _run(PdfFile file) => ContentInterpreter(file).run(file.pages[0]);

const _helvetica =
    '/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>';

/// [list] painted at one pixel a point, as RGBA.
Future<(Uint8List, int)> _paint(WidgetTester tester, PageDisplayList list) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(list.widthPts, list.heightPts);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: CustomPaint(
      size: Size(list.widthPts, list.heightPts),
      painter: PageListPainter(
        list: list,
        runs: mergeRuns(list.texts),
        images: const {},
        serifFamily: 'Inter',
        sansFamily: 'Inter',
      ),
    ),
  ));
  final bytes = await tester.runAsync(() async {
    final image = await (key.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  });
  return (bytes!, list.widthPts.toInt());
}

List<int> _at((Uint8List, int) pixels, int x, int y) {
  final (bytes, width) = pixels;
  final i = (y * width + x) * 4;
  return bytes.sublist(i, i + 3);
}

const _white = [255, 255, 255];
const _red = [255, 0, 0];

void main() {
  group('clipping', () {
    test('a W narrows what follows it, and Q gives it back', () {
      final list = _run(_page(
        'q 10 10 50 50 re W n 1 0 0 rg 0 0 200 200 re f Q '
        '0 0 1 rg 150 150 20 20 re f',
      ));
      expect(list.clips, hasLength(1));
      expect(list.clips.single.paths.single.evenOdd, isFalse);
      expect(list.paths[0].clip, 0);
      expect(list.paths[1].clip, kNoClip);
    });

    test('the path that sets a clip is painted outside it', () {
      final list = _run(_page('10 10 50 50 re W f 0 0 20 20 re f'));
      expect(list.paths[0].clip, kNoClip);
      expect(list.paths[1].clip, 0);
    });

    test('W* keeps its even odd rule, and clips nest', () {
      final list = _run(_page(
        '0 0 100 100 re W* n 10 10 50 50 re W n 0 0 200 200 re f',
      ));
      expect(list.clips, hasLength(2));
      expect(list.clips[0].paths.single.evenOdd, isTrue);
      expect(list.clips[1].paths, hasLength(2));
      expect(list.paths.single.clip, 1);
    });

    test('text in two clips is never merged into one line', () {
      final list = _run(_page(
        'BT /F1 12 Tf 10 100 Td (left) Tj ET '
        'q 0 0 200 200 re W n BT /F1 12 Tf 36 100 Td (right) Tj ET Q',
        resources: _helvetica,
      ));
      expect(list.texts.map((t) => t.clip), [kNoClip, 0]);
      expect(mergeRuns(list.texts), hasLength(2));
    });

    test('a form draws inside its own box', () {
      final file = PdfFile.open(buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
            '/Resources << /XObject << /X1 5 0 R >> >> /Contents 4 0 R >>'),
        streamObj('', ascii.encode('/X1 Do')),
        streamObj('/Type /XObject /Subtype /Form /BBox [0 0 40 40]',
            ascii.encode('0 0 200 200 re f')),
      ]));
      final list = _run(file);
      expect(list.paths.single.clip, 0);
      expect(list.clips.single.paths.single.segs, hasLength(5));
    });

    testWidgets('nothing is painted outside a clip', (tester) async {
      final pixels = await _paint(
        tester,
        _run(_page('q 10 10 50 50 re W n 1 0 0 rg 0 0 200 200 re f Q')),
      );
      // PDF y 10 to 60 is top-left y 140 to 190.
      expect(_at(pixels, 30, 160), _red);
      expect(_at(pixels, 100, 100), _white);
      expect(_at(pixels, 30, 100), _white);
    });
  });

  group('shadings', () {
    const axial = '/Shading << /S0 << /ShadingType 2 /ColorSpace /DeviceRGB '
        '/Coords [0 0 200 0] /Extend [true true] /Function << '
        '/FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >> >>';

    test('sh is drawn as a blend, no longer skipped', () {
      final interpreter = ContentInterpreter(_page('/S0 sh', resources: axial));
      final list = interpreter.run(interpreter.doc.pages[0]);
      expect(interpreter.unsupported, isEmpty);
      final shade = list.shades.single;
      expect(shade.radial, isFalse);
      expect(shade.colors.first, 0xFFFF0000);
      expect(shade.colors.last, 0xFF0000FF);
    });

    testWidgets('an axial blend runs the way the file set it', (tester) async {
      final pixels = await _paint(tester, _run(_page('/S0 sh', resources: axial)));
      final left = _at(pixels, 5, 100);
      final right = _at(pixels, 195, 100);
      expect(left[0], greaterThan(230));
      expect(left[2], lessThan(25));
      expect(right[2], greaterThan(230));
      expect(right[0], lessThan(25));
    });

    testWidgets('a shading pattern fills only its path', (tester) async {
      const pattern = '/Pattern << /P0 << /PatternType 2 /Shading << '
          '/ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] '
          '/Extend [true true] /Function << /FunctionType 2 /Domain [0 1] '
          '/C0 [1 0 0] /C1 [1 0 0] /N 1 >> >> >> >>';
      final list = _run(_page(
        '/Pattern cs /P0 scn 0 0 100 100 re f',
        resources: pattern,
      ));
      expect(list.paths, isEmpty);
      expect(list.shades.single.clip, 0);
      final pixels = await _paint(tester, list);
      expect(_at(pixels, 50, 150), _red);
      expect(_at(pixels, 150, 50), _white);
    });

    test('a colour set after a pattern fills flat again', () {
      const pattern = '/Pattern << /P0 << /PatternType 2 /Shading << '
          '/ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 1 0] '
          '/Function << /FunctionType 2 /C0 [0] /C1 [1] /N 1 >> >> >> >>';
      final list = _run(_page(
        '/Pattern cs /P0 scn 0 0 10 10 re f 0 g 20 20 10 10 re f',
        resources: pattern,
      ));
      expect(list.shades, hasLength(1));
      expect(list.paths.single.fill, isTrue);
    });

    test('a mesh shading is reported, not drawn wrong', () {
      final interpreter = ContentInterpreter(_page(
        '/S0 sh',
        resources: '/Shading << /S0 << /ShadingType 4 >> >>',
      ));
      final list = interpreter.run(interpreter.doc.pages[0]);
      expect(list.shades, isEmpty);
      expect(interpreter.unsupported, contains('sh:type4'));
    });
  });

  group('functions and colours', () {
    PdfFile holding(String body) => PdfFile.open(buildPdf([
          obj('<< /Type /Catalog /Pages 2 0 R >>'),
          obj('<< /Type /Pages /Kids [] /Count 0 >>'),
          obj(body),
        ]));

    PdfFunction calculator(String program, {String range = '[0 1]'}) {
      final file = PdfFile.open(buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [] /Count 0 >>'),
        streamObj('/FunctionType 4 /Domain [0 1] /Range $range',
            ascii.encode(program)),
      ]));
      return PdfFunction.read(file, file.getObject(3))!;
    }

    test('a PostScript calculator runs its arithmetic and its branches', () {
      final f = calculator('{ 2 mul 1 exch sub dup 0 lt { pop 0 } if }');
      expect(f([0.25]).single, closeTo(0.5, 1e-9));
      expect(f([0.9]).single, 0);
      final g = calculator(
        '{ dup 0.5 gt { pop 1 0 } { 0 exch } ifelse }',
        range: '[0 1 0 1]',
      );
      expect(g([0.8]), [1, 0]);
      expect(g([0.2]), [0, 0.2]);
    });

    test('a malformed program is refused rather than guessed at', () {
      final f = calculator('{ { 1 } { 1 } ifelse }');
      expect(() => f([0.5]), throwsA(anything));
    });

    test('a stitching function hands each stretch to its own function', () {
      final file = holding('<< /FunctionType 3 /Domain [0 1] /Bounds [0.5] '
          '/Encode [0 1 0 1] /Functions [ '
          '<< /FunctionType 2 /C0 [0] /C1 [1] /N 1 >> '
          '<< /FunctionType 2 /C0 [1] /C1 [0] /N 1 >> ] >>');
      final f = PdfFunction.read(file, file.getObject(3))!;
      expect(f([0.25]).single, closeTo(0.5, 1e-9));
      expect(f([0.75]).single, closeTo(0.5, 1e-9));
      expect(f([0.5]).single, closeTo(1, 1e-9));
    });

    test('a Separation colour goes through its tint transform', () {
      final file = holding('[/Separation /Spot /DeviceCMYK '
          '<< /FunctionType 2 /C0 [0 0 0 0] /C1 [0 1 1 0] /N 1 >>]');
      final space = PdfColourSpace.read(file, file.getObject(3))!;
      expect(space.components, 1);
      expect(space.argb([1]), 0xFFFF0000);
      expect(space.argb([0]), 0xFFFFFFFF);
    });
  });

  test('a ligature is spelt out, so it draws and it is found', () {
    expect(expandLigatures('ﬁnd the ﬂow'), 'find the flow');
    expect(expandLigatures('plain'), 'plain');
  });
}
