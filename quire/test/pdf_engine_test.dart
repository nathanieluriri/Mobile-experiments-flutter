import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/pdf_page_painter.dart';
import 'package:quire/pdf/crypt.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/encodings.dart';
import 'package:quire/pdf/filters.dart';
import 'package:quire/pdf/font.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/lexer.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/pdf/pdf_search.dart';
import 'package:quire/pdf/standard_metrics.dart';
import 'package:quire/pdf/truetype.dart';

// ---------------------------------------------------------------- fixtures

/// Opens one of the documents this app ships.
PdfFile bundled(String name) =>
    PdfFile.open(File('assets/documents/$name.pdf').readAsBytesSync());

/// The whole reading order text of a page, one merged line per element.
String pageText(PdfFile doc, int index, {double? wordGapEm}) {
  final dl = ContentInterpreter(doc).run(doc.pages[index]);
  final runs = wordGapEm == null
      ? mergeRuns(dl.texts)
      : mergeRuns(dl.texts, wordGapEm: wordGapEm);
  return runs.map((r) => r.text).join('\n');
}

/// Assembles a small but genuine PDF: header, numbered objects, a classic
/// cross reference table with real offsets, a trailer and startxref.
///
/// The engine's harder paths (a lying /Length, an invisible render mode, an
/// /ExtGState alpha, an indexed image) cannot be reached from the two bundled
/// documents, and a fixture file checked into the repo would hide what it is
/// testing inside a blob. Building the bytes in the test states the case in
/// the open.
Uint8List buildPdf(List<List<int>> objects, {String trailerExtra = ''}) {
  final out = <int>[];
  void add(String s) => out.addAll(ascii.encode(s));
  add('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n');
    out.addAll(objects[i]);
    add('\nendobj\n');
  }
  final xrefAt = out.length;
  add('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    add('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  add('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R $trailerExtra>>\n');
  add('startxref\n$xrefAt\n%%EOF\n');
  return Uint8List.fromList(out);
}

List<int> obj(String body) => ascii.encode(body);

/// A stream object. [lengthOverride] writes a /Length the data does not have,
/// which is how a producer that miscounts its own stream is simulated.
List<int> streamObj(String dict, List<int> data, {int? lengthOverride}) => [
      ...ascii.encode('<< $dict /Length ${lengthOverride ?? data.length} >>\n'
          'stream\n'),
      ...data,
      ...ascii.encode('\nendstream'),
    ];

/// A one page document whose content stream is [content], with [resources]
/// spliced into the page dictionary.
Uint8List onePage(String content, {String resources = ''}) => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << $resources >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode(content)),
    ]);

const String kHelveticaRes =
    '/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >>';

TextRunCmd run(String text, double x, double y,
        {double size = 10, double? width, int seq = 0}) =>
    TextRunCmd(
      text: text,
      x: x,
      y: y,
      fontSize: size,
      widthPts: width ?? size * 0.5 * text.length,
      fontKey: 'F1',
      bold: false,
      italic: false,
      serif: false,
      mono: false,
      color: 0xFF000000,
      rotated: false,
      seq: seq,
    );

void main() {
  // -------------------------------------------------------------- the files

  group('the bundled documents', () {
    test('field-guide-to-paper opens six pages from a classic xref', () {
      final doc = bundled('field-guide-to-paper');
      expect(doc.pageCount, 6);
      expect(doc.encrypted, isFalse);
      expect(doc.recoveredByScan, isFalse,
          reason: 'a healthy file must be read from its xref, not scanned');
      expect(doc.xref.length, greaterThan(6));
      final box = doc.mediaBox(doc.pages[0]);
      expect(box, [0.0, 0.0, 612.0, 792.0]);
      expect(doc.dict(doc.trailer['Root'])!.containsKey('Outlines'), isTrue);
    });

    test('field-guide-to-paper streams are Flate compressed', () {
      final doc = bundled('field-guide-to-paper');
      final contents = doc.resolve(doc.pages[1]['Contents']) as PdfStream;
      expect(doc.streamFilters(contents), ['FlateDecode']);
      expect(doc.decodeStream(contents).length,
          greaterThan(contents.raw.length),
          reason: 'inflating must produce more bytes than it consumed');
    });

    test('press-lease opens two entirely uncompressed pages', () {
      final doc = bundled('press-lease');
      expect(doc.pageCount, 2);
      expect(doc.encrypted, isFalse);
      for (var p = 0; p < 2; p++) {
        final contents = doc.resolve(doc.pages[p]['Contents']) as PdfStream;
        expect(doc.streamFilters(contents), isEmpty,
            reason: 'this file is the proof that a Flate-only reader is not '
                'enough: page $p carries no filter at all');
      }
    });

    test('press-lease yields real text despite having no filter', () {
      final doc = bundled('press-lease');
      final first = pageText(doc, 0);
      expect(first, startsWith('EQUIPMENT LEASE AGREEMENT'));
      expect(first, contains('Quire Press reference QP-LSE-0114.'));
      expect(first, contains('Hollow Ridge Machine Company'));
      expect(first.length, greaterThan(2500));
      final second = pageText(doc, 1);
      expect(second, startsWith('EQUIPMENT LEASE AGREEMENT, CONTINUED'));
      expect(second, contains('Loss and damage.'));
    });

    test('field-guide-to-paper yields real text from every page', () {
      final doc = bundled('field-guide-to-paper');
      final texts = [for (var p = 0; p < 6; p++) pageText(doc, p)];
      expect(texts[0], contains('A Field Guide to Paper'));
      expect(texts[1], contains('Reading a Sheet'));
      expect(texts[2], contains('Weight, and the Two Ways We Measure It'));
      expect(texts[3], contains('A Working Table of Stocks'));
      expect(texts[4], contains('Grain and the Folding Scheme'));
      expect(texts[5], contains('The Look of a Laid Sheet'));
      for (final t in texts) {
        expect(t.length, greaterThan(250));
      }
    });
  });

  // ------------------------------------------------------------------ fonts

  group('fonts and encodings', () {
    test('both bundled files rely on the standard fourteen metrics', () {
      for (final name in ['field-guide-to-paper', 'press-lease']) {
        final doc = bundled(name);
        final fonts = doc.dict(doc.dict(doc.pages[0]['Resources'])!['Font'])!;
        expect(fonts.keys.toList(), ['F1', 'F2', 'F3', 'F4']);
        for (final e in fonts.entries) {
          final font = PdfFont.load(doc, doc.dict(e.value)!);
          expect(font.widths, isEmpty,
              reason: '$name/${e.key} ships no /Widths array, so the width '
                  'table is the only thing that can lay it out');
        }
      }
    });

    test('a width table is indexed by character code, not by code minus 32',
        () {
      final doc = bundled('field-guide-to-paper');
      final fonts = doc.dict(doc.dict(doc.pages[0]['Resources'])!['Font'])!;
      final helvetica = PdfFont.load(doc, doc.dict(fonts['F3'])!);
      expect(helvetica.baseFont, 'Helvetica');
      // Adobe's published Helvetica metrics, in 1000ths of an em.
      expect(helvetica.widthOf(0x41), 667); // A
      expect(helvetica.widthOf(0x69), 222); // i
      expect(helvetica.widthOf(0x20), 278); // space
      expect(helvetica.widthOf(0x57), 944); // W
      final times = PdfFont.load(doc, doc.dict(fonts['F1'])!);
      expect(times.baseFont, 'Times-Roman');
      expect(times.widthOf(0x41), 722); // A
      expect(times.widthOf(0x69), 278); // i
    });

    test('two fonts carry a ToUnicode CMap and two fall back to WinAnsi', () {
      final doc = bundled('field-guide-to-paper');
      final fonts = doc.dict(doc.dict(doc.pages[0]['Resources'])!['Font'])!;
      final loaded = {
        for (final e in fonts.entries) e.key: PdfFont.load(doc, doc.dict(e.value)!)
      };
      expect(loaded['F1']!.hasToUnicode, isTrue);
      expect(loaded['F2']!.hasToUnicode, isTrue);
      expect(loaded['F3']!.hasToUnicode, isFalse);
      expect(loaded['F4']!.hasToUnicode, isFalse);
      for (final f in loaded.values) {
        expect(f.baseEncoding, 'WinAnsiEncoding');
      }
    });

    test('the WinAnsi fallback decodes the same ASCII as a ToUnicode CMap', () {
      final doc = bundled('field-guide-to-paper');
      final fonts = doc.dict(doc.dict(doc.pages[0]['Resources'])!['Font'])!;
      final withCMap = PdfFont.load(doc, doc.dict(fonts['F1'])!);
      final withoutCMap = PdfFont.load(doc, doc.dict(fonts['F3'])!);
      final bytes = Uint8List.fromList(ascii.encode('QUIRE PRESS 1874!'));
      String textOf(PdfFont f) => f.decode(bytes).map((c) => c.text).join();
      expect(textOf(withoutCMap), 'QUIRE PRESS 1874!');
      expect(textOf(withCMap), textOf(withoutCMap));
      // And the page proves it end to end: the wordmark is set in F3.
      expect(pageText(doc, 0), contains('QUIRE PRESS'));
    });

    test('WinAnsi and MacRoman diverge above 0x7F', () {
      expect(decodeSingleByte(0x93, 'WinAnsiEncoding'), 0x201C);
      expect(decodeSingleByte(0x93, 'MacRomanEncoding'), 0x00EC);
      expect(decodeSingleByte(0x41, 'WinAnsiEncoding'), 0x41);
      expect(unicodeForGlyphName('fi'), 0xFB01);
      expect(unicodeForGlyphName('uni20AC'), 0x20AC);
      expect(unicodeForGlyphName('g42'), isNull);
    });

    test('the standard fourteen tables are complete and correct', () {
      for (final name in [
        'helvetica',
        'helvetica-bold',
        'times-roman',
        'times-bolditalic',
        'symbol',
        'zapfdingbats',
        'courier'
      ]) {
        expect(standardWidths(name), hasLength(256), reason: name);
        expect(isStandardFontName(name), isTrue);
      }
      expect(standardWidths('comic-sans'), isNull);
      expect(isStandardFontName('comic-sans'), isFalse);
      expect(kHelvetica[0x41], closeTo(0.667, 1e-9));
      expect(kHelveticaBold[0x41], closeTo(0.722, 1e-9));
      expect(kTimesRoman[0x20], closeTo(0.250, 1e-9));
      expect(kCourier[0x41], closeTo(0.600, 1e-9));
      expect(kCourier.toSet(), {0.600},
          reason: 'Courier is monospaced, every advance is the same');
    });

    test('a ToUnicode CMap decodes bfchar and bfrange', () {
      final cmap = ascii.encode('''
/CIDInit /ProcSet findresource begin
2 beginbfchar
<0041> <0061>
<0042> <00660066>
endbfchar
1 beginbfrange
<0050> <0052> <0070>
endbfrange
''');
      final out = <int, String>{};
      parseCMap(Uint8List.fromList(cmap), out);
      expect(out[0x41], 'a');
      expect(out[0x42], 'ff');
      expect(out[0x50], 'p');
      expect(out[0x51], 'q');
      expect(out[0x52], 'r');
      expect(out.containsKey(0x53), isFalse);
    });
  });

  // ------------------------------------------------------------ run merging

  group('run merging', () {
    test('the tuned word gap sits inside the band the corpus leaves open', () {
      // Swept over eleven real PDFs against a reference extractor: below
      // 0.023 words shatter into stray letters, above 0.028 real word breaks
      // start being swallowed. 0.026 is the middle of that band.
      expect(kWordGapEm, 0.026);
      expect(kWordGapEm, greaterThan(0.023));
      expect(kWordGapEm, lessThan(0.030));
    });

    test('a gap under the threshold is kerning and a gap over it is a space',
        () {
      // Two fragments 0.02em apart, then two 0.05em apart, same baseline.
      final tight = mergeRuns([
        run('outsi', 0, 100, width: 25),
        run('de', 25.2, 100, width: 10),
      ]);
      expect(tight.single.text, 'outside');
      final loose = mergeRuns([
        run('these', 0, 100, width: 25),
        run('are', 25.5, 100, width: 15),
      ]);
      expect(loose.single.text, 'these are');
    });

    test('merging keeps the seq of the first run in the line', () {
      final merged = mergeRuns([
        run('one ', 0, 100, width: 20, seq: 7),
        run('two', 20, 100, width: 15, seq: 8),
        run('next', 0, 130, width: 20, seq: 9),
      ]);
      expect(merged.map((r) => r.text).toList(), ['one two', 'next']);
      expect(merged[0].seq, 7);
      expect(merged[1].seq, 9);
    });

    test('a merged run reports the box it paints into', () {
      final r = mergeRuns([run('abcd', 10, 100, size: 10, width: 40)]).single;
      expect(r.bounds.left, 10);
      expect(r.bounds.top, closeTo(92, 1e-9));
      expect(r.bounds.width, 40);
      expect(r.bounds.height, 10);
      expect(r.sliceBounds(2, 4).left, closeTo(30, 1e-9));
      expect(r.sliceBounds(2, 4).width, closeTo(20, 1e-9));
    });

    test('a dense page collapses thousands of runs into readable lines', () {
      final doc = bundled('field-guide-to-paper');
      final dl = ContentInterpreter(doc).run(doc.pages[2]);
      expect(dl.texts.length, greaterThan(400));
      final merged = mergeRuns(dl.texts);
      expect(merged.length, lessThan(dl.texts.length ~/ 5));
      expect(merged.first.text, 'TWO');
    });

    test('every word break in the bundled files is an explicit space glyph',
        () {
      // Which is why these two documents cannot be used to tune the threshold:
      // the merged text is identical whether the threshold is far below or far
      // above every gap they contain. It is still the assertion that catches a
      // regression in the merge itself.
      for (final name in ['field-guide-to-paper', 'press-lease']) {
        final doc = bundled(name);
        for (var p = 0; p < doc.pageCount; p++) {
          final tight = pageText(doc, p, wordGapEm: 0.001);
          final loose = pageText(doc, p, wordGapEm: 0.600);
          expect(tight, loose, reason: '$name page $p');
          expect(pageText(doc, p), tight);
        }
      }
    });

    test('no line in either bundled file is broken into stray letters', () {
      final stray = RegExp(r'(?<=\s)[b-hj-z](?=\s)');
      for (final name in ['field-guide-to-paper', 'press-lease']) {
        final doc = bundled(name);
        for (var p = 0; p < doc.pageCount; p++) {
          expect(stray.hasMatch(pageText(doc, p)), isFalse,
              reason: '$name page $p reads as broken letters');
        }
      }
    });
  });

  // -------------------------------------------------------------- the z order

  group('paint order', () {
    test('every command on a page carries a distinct sequence number', () {
      for (final name in ['field-guide-to-paper', 'press-lease']) {
        final doc = bundled(name);
        for (var p = 0; p < doc.pageCount; p++) {
          final dl = ContentInterpreter(doc).run(doc.pages[p]);
          final seqs = [
            ...dl.texts.map((e) => e.seq),
            ...dl.paths.map((e) => e.seq),
            ...dl.images.map((e) => e.seq),
          ];
          expect(seqs.toSet(), hasLength(seqs.length), reason: '$name p$p');
          expect(seqs.reduce((a, b) => a < b ? a : b), 0);
        }
      }
    });

    test('the photograph page interleaves its image between its commands', () {
      final doc = bundled('field-guide-to-paper');
      final dl = ContentInterpreter(doc).run(doc.pages[5]);
      expect(dl.images, hasLength(1));
      final image = dl.images.single;
      final maxSeq = dl.texts.map((t) => t.seq).reduce((a, b) => a > b ? a : b);
      final minSeq = dl.texts.map((t) => t.seq).reduce((a, b) => a < b ? a : b);
      expect(image.seq, greaterThan(minSeq));
      expect(image.seq, lessThan(maxSeq),
          reason: 'painting images in their own pass would move this '
              'photograph over the caption that belongs on top of it');
    });

    test('image coverage measures the fraction of the page a picture holds',
        () {
      final doc = bundled('field-guide-to-paper');
      expect(ContentInterpreter(doc).run(doc.pages[5]).imageCoverage,
          closeTo(0.349, 0.005));
      expect(ContentInterpreter(doc).run(doc.pages[0]).imageCoverage, 0);
    });
  });

  // ------------------------------------------- the traps this format sets

  group('the traps a PDF reader falls into', () {
    test('a dictionary tells a missing value apart from the next key', () {
      final lx = PdfLexer(Uint8List.fromList(
          ascii.encode('<< /Subtype /Type1 /Length 12 0 R /Count 3 '
              '/Kids [4 0 R 5 0 R] >>')));
      final d = lx.parseObject()! as Map<String, Object?>;
      expect(d['Subtype'], const PdfName('Type1'),
          reason: 'breaking the value loop on any slash makes every font '
              'come back empty');
      expect(d['Length'], const PdfRef(12, 0));
      expect(d['Count'], 3);
      expect(d['Kids'], [const PdfRef(4, 0), const PdfRef(5, 0)]);
    });

    test('a trailer key with no value does not report the file as encrypted',
        () {
      final bytes = onePage('BT ET', resources: kHelveticaRes);
      final withNull = Uint8List.fromList(ascii
          .encode(ascii.decode(bytes).replaceFirst('/Root 1 0 R ', '/Root 1 0 R /Encrypt ')));
      final doc = PdfFile.open(withNull);
      expect(doc.trailer.containsKey('Encrypt'), isTrue,
          reason: 'the key is present, which is exactly the trap');
      expect(doc.trailer['Encrypt'], isNull);
      expect(doc.encrypted, isFalse,
          reason: 'encryption is decided by the value, never by the key');
    });

    test('a trailer with a real /Encrypt does not open on a guess', () {
      // The dictionary carries no /O and no /U, so no password can be checked
      // against it and none is claimed to have been tried. Handing back a page
      // tree read through a key nothing verified would be the failure that
      // looks like success: uniform noise presented as a document.
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>'),
        obj('<< /Filter /Standard /V 2 /R 3 >>'),
      ], trailerExtra: '/Encrypt 4 0 R ');
      expect(
        () => PdfFile.open(bytes),
        throwsA(
          isA<PdfLocked>()
              .having((e) => e.cipher, 'cipher', kCipherRc4)
              .having((e) => e.wrongPassword, 'wrongPassword', isFalse),
        ),
      );
      final security = PdfFile.securityOf(bytes)!;
      expect(security.version, 2);
      expect(security.revision, 3);
    });

    test('a stream whose /Length lies is recovered by finding endstream', () {
      final content = 'BT /F1 12 Tf 20 150 Td (RECOVERED) Tj ET';
      final bytes = buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
            '/Resources << $kHelveticaRes >> /Contents 4 0 R >>'),
        streamObj('', ascii.encode(content), lengthOverride: 3),
      ]);
      final doc = PdfFile.open(bytes);
      final stream = doc.resolve(doc.pages[0]['Contents']) as PdfStream;
      expect(stream.dict['Length'], 3, reason: 'the file really does say 3');
      expect(stream.raw.length, content.length,
          reason: 'and the reader really does ignore it');
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.texts.single.text, 'RECOVERED');
    });

    test('render modes 3 and 7 are not painted but still advance the text', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 12 Tf 10 100 Td 3 Tr (HIDDEN) Tj 0 Tr (SHOWN) Tj '
        '7 Tr (ALSOHIDDEN) Tj ET',
        resources: kHelveticaRes,
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.texts.map((t) => t.text).toList(), ['SHOWN'],
          reason: 'the invisible OCR layer over a scan must never be painted');
      // HIDDEN in Helvetica at 12pt is H+I+D+D+E+N = 3833/1000 em.
      expect(dl.texts.single.x, closeTo(10 + 3.833 * 12, 0.05),
          reason: 'skipping the paint must not skip the text matrix');
    });

    testWidgets('a decoded page image can be handed to the engine inside '
        'runAsync', (WidgetTester tester) async {
      // Awaiting a dart:ui decode directly inside testWidgets hangs the run
      // for the whole timeout with no output, because the fake async zone
      // never pumps the engine.
      final doc = bundled('field-guide-to-paper');
      final cmd = ContentInterpreter(doc).run(doc.pages[5]).images.single;
      expect(cmd.encoding, 'raw-rgb');
      expect(cmd.width, 600);
      expect(cmd.height, 400);
      expect(cmd.bytes, hasLength(600 * 400 * 3));

      late ui.Image image;
      await tester.runAsync(() async {
        final rgb = cmd.bytes!;
        final rgba = Uint8List(600 * 400 * 4);
        for (var i = 0, o = 0; i < rgb.length; i += 3, o += 4) {
          rgba[o] = rgb[i];
          rgba[o + 1] = rgb[i + 1];
          rgba[o + 2] = rgb[i + 2];
          rgba[o + 3] = 0xFF;
        }
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
            rgba, 600, 400, ui.PixelFormat.rgba8888, completer.complete);
        image = await completer.future;
      });
      expect(image.width, 600);
      expect(image.height, 400);
      image.dispose();
    });
  });

  // -------------------------------------------------------- the three fixes

  group('graphics state alpha', () {
    test('the gs operator applies /ca to fills and /CA to strokes', () {
      final doc = PdfFile.open(onePage(
        'q /GS0 gs 1 0 0 rg 0 0 1 RG 10 10 50 50 re B Q '
        '1 0 0 rg 0 0 1 RG 10 10 50 50 re B',
        resources: '/ExtGState << /GS0 << /ca 0.5 /CA 0.25 >> >>',
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.paths, hasLength(2));
      expect(dl.paths[0].fillColor, 0x80FF0000);
      expect(dl.paths[0].strokeColor, 0x400000FF);
      expect(dl.paths[1].fillColor, 0xFFFF0000,
          reason: 'the alpha was inside q...Q and must not survive it');
      expect(dl.paths[1].strokeColor, 0xFF0000FF);
    });

    test('an alpha set before a colour still reaches that colour', () {
      final doc = PdfFile.open(onePage(
        '/GS0 gs 0 0 0 rg 0 0 20 20 re f 0 1 0 rg 0 0 20 20 re f',
        resources: '/ExtGState << /GS0 << /ca 0.2 >> >>',
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.paths[0].fillColor, 0x33000000);
      expect(dl.paths[1].fillColor, 0x3300FF00);
    });

    test('gs alpha reaches text as well as paths', () {
      final doc = PdfFile.open(onePage(
        '/GS0 gs BT /F1 12 Tf 10 100 Td 1 0 0 rg (FADED) Tj ET',
        resources: '$kHelveticaRes '
            '/ExtGState << /GS0 << /ca 0.5 /CA 0.5 >> >>',
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.texts.single.color, 0x80FF0000);
    });

    test('an ExtGState line width is honoured and gs is no longer unsupported',
        () {
      final doc = PdfFile.open(onePage(
        '/GS0 gs 0 0 20 20 re S',
        resources: '/ExtGState << /GS0 << /LW 4 >> >>',
      ));
      final interpreter = ContentInterpreter(doc);
      final dl = interpreter.run(doc.pages[0]);
      expect(dl.paths.single.lineWidth, 4);
      expect(interpreter.unsupported, isNot(contains('gs')));
    });

    test('a missing ExtGState resource leaves the state alone', () {
      final doc = PdfFile.open(onePage('/Nope gs 1 0 0 rg 0 0 20 20 re f'));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.paths.single.fillColor, 0xFFFF0000);
    });
  });

  group('image colour spaces', () {
    test('an 8 bit indexed image expands through its palette', () {
      final doc = PdfFile.open(indexedEightBit());
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-rgb');
      expect(image.width, 3);
      expect(image.height, 1);
      expect(image.bytes, [255, 0, 0, 0, 255, 0, 0, 0, 255]);
    });

    test('a 4 bit indexed image unpacks two pixels per byte', () {
      final doc = PdfFile.open(indexedFourBit());
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-rgb');
      expect(image.width, 3);
      expect(image.bytes, [255, 0, 0, 0, 255, 0, 255, 0, 0],
          reason: 'a row of an image is padded to a whole byte, so the third '
              'pixel is the high nibble of the second byte');
    });

    test('an 8 bit CMYK image converts to RGB', () {
      final doc = PdfFile.open(cmykImage());
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-rgb');
      expect(image.width, 3);
      expect(image.bytes, [0, 255, 255, 0, 0, 0, 255, 255, 255]);
    });

    test('an ICCBased three component image is treated as RGB', () {
      final doc = PdfFile.open(iccImage());
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-rgb');
      expect(image.bytes, [1, 2, 3, 4, 5, 6]);
    });

    test('a one bit grey image unpacks to one byte a pixel', () {
      final doc = PdfFile.open(bilevelImage());
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-gray');
      expect(image.width, 10);
      expect(image.height, 2);
      // Row one is 1010101010, row two is all ones, each padded to two bytes.
      expect(image.bytes!.sublist(0, 10),
          [255, 0, 255, 0, 255, 0, 255, 0, 255, 0]);
      expect(image.bytes!.sublist(10), List.filled(10, 255));
    });

    test('a /Decode array reverses a one bit image', () {
      final doc = PdfFile.open(bilevelImage(extra: '/Decode [1 0] '));
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.bytes!.sublist(0, 10),
          [0, 255, 0, 255, 0, 255, 0, 255, 0, 255]);
    });

    test('an image mask stays packed, because it is not a picture', () {
      final doc = PdfFile.open(bilevelImage(extra: '/ImageMask true '));
      final image = ContentInterpreter(doc).run(doc.pages[0]).images.single;
      expect(image.encoding, 'raw-bilevel');
      expect(image.bytes, hasLength(4));
    });

    test('an encoding we cannot read is named, never guessed at', () {
      final doc = PdfFile.open(jpxImage());
      final interpreter = ContentInterpreter(doc);
      final image = interpreter.run(doc.pages[0]).images.single;
      expect(image.encoding, 'jpx');
      expect(image.bytes, isNull);
      expect(interpreter.unsupported, contains('image:jpx'));
    });
  });

  // ----------------------------------------------------------- resilience

  group('resilience', () {
    test('a broken startxref falls through to a full object scan', () {
      final good = File('assets/documents/press-lease.pdf').readAsBytesSync();
      final text = ascii.decode(good, allowInvalid: true);
      final at = text.lastIndexOf('startxref') + 'startxref'.length;
      final broken = Uint8List.fromList(good);
      // Overwrite the offset digits with an offset past the end of the file.
      var i = at;
      while (i < broken.length && (broken[i] < 0x30 || broken[i] > 0x39)) {
        i++;
      }
      while (i < broken.length && broken[i] >= 0x30 && broken[i] <= 0x39) {
        broken[i++] = 0x39;
      }
      final doc = PdfFile.open(broken);
      expect(doc.recoveredByScan, isTrue);
      expect(doc.pageCount, 2, reason: 'recovery must find every page');
      expect(pageText(doc, 0), contains('EQUIPMENT LEASE AGREEMENT'));
    });

    test('a truncated file opens without throwing', () {
      final good = File('assets/documents/press-lease.pdf').readAsBytesSync();
      final half = Uint8List.sublistView(good, 0, good.length ~/ 2);
      late PdfFile doc;
      expect(() => doc = PdfFile.open(half), returnsNormally);
      expect(doc.recoveredByScan, isTrue);
      expect(doc.pageCount, lessThanOrEqualTo(2));
    });

    test('garbage bytes open to an empty document rather than an exception',
        () {
      final junk = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));
      late PdfFile doc;
      expect(() => doc = PdfFile.open(junk), returnsNormally);
      expect(doc.pageCount, 0);
      expect(doc.encrypted, isFalse);
    });

    test('the circuit breaker stops a pathological content stream', () {
      final content = StringBuffer('BT /F1 12 Tf ');
      for (var i = 0; i < 500; i++) {
        content.write('1 0 0 1 10 ${i % 190} Tm (x) Tj ');
      }
      content.write('ET');
      final doc = PdfFile.open(
          onePage(content.toString(), resources: kHelveticaRes));
      final full = ContentInterpreter(doc);
      expect(full.maxOps, 400000);
      expect(full.run(doc.pages[0]).texts, hasLength(500));

      final capped = ContentInterpreter(doc, maxOps: 100);
      final dl = capped.run(doc.pages[0]);
      expect(dl.texts.length, lessThan(60));
      expect(capped.opsRun, lessThanOrEqualTo(102));
    });

    test('a page tree that points at itself terminates', () {
      final doc = PdfFile.open(buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [2 0 R 3 0 R] /Count 1 >>'),
        obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>'),
      ]));
      expect(doc.pageCount, 1);
    });

    test('a page inherits Resources and MediaBox from its parent', () {
      final doc = PdfFile.open(buildPdf([
        obj('<< /Type /Catalog /Pages 2 0 R >>'),
        obj('<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 300 400] '
            '/Resources << $kHelveticaRes >> >>'),
        obj('<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>'),
        streamObj('', ascii.encode('BT /F1 12 Tf 10 10 Td (INHERITED) Tj ET')),
      ]));
      expect(doc.mediaBox(doc.pages[0]), [0.0, 0.0, 300.0, 400.0]);
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.widthPts, 300);
      expect(dl.heightPts, 400);
      expect(dl.texts.single.text, 'INHERITED');
    });
  });

  // -------------------------------------------------------------- filters

  group('stream filters', () {
    test('ASCII85 round trips a known payload', () {
      expect(ascii.decode(ascii85Decode(Uint8List.fromList(
              ascii.encode('87cURD_*#4DfTZ)~>')))),
          'Hello, World');
      expect(ascii85Decode(Uint8List.fromList(ascii.encode('z~>'))),
          [0, 0, 0, 0]);
    });

    test('ASCIIHex ignores whitespace and pads an odd digit', () {
      expect(asciiHexDecode(Uint8List.fromList(ascii.encode('48 65 6C6C 6F>'))),
          [0x48, 0x65, 0x6C, 0x6C, 0x6F]);
      expect(asciiHexDecode(Uint8List.fromList(ascii.encode('4>'))), [0x40]);
    });

    test('RunLength expands literal and repeated stretches', () {
      expect(
          runLengthDecode(Uint8List.fromList([2, 1, 2, 3, 254, 9, 128, 7])),
          [1, 2, 3, 9, 9, 9]);
    });

    test('the PNG up predictor adds the row above', () {
      final data = Uint8List.fromList([
        0, 1, 2, 3, // filter 0, raw row
        2, 10, 20, 30, // filter 2, add previous row
      ]);
      final out = applyPredictor(data,
          predictor: 12, colors: 1, bpc: 8, columns: 3);
      expect(out, [1, 2, 3, 11, 22, 33]);
    });

    test('the TIFF predictor adds the pixel to the left', () {
      final data = Uint8List.fromList([1, 1, 1, 1]);
      final out = applyPredictor(data,
          predictor: 2, colors: 1, bpc: 8, columns: 4);
      expect(out, [1, 2, 3, 4]);
    });

    test('LZW decodes a stream and honours early change', () {
      // "-----A---B" from the PDF specification's own worked example.
      final data = Uint8List.fromList(
          [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]);
      expect(ascii.decode(lzwDecode(data)), '-----A---B');
    });

    test('inflate reads a real stream and gives up quietly on garbage', () {
      final doc = bundled('field-guide-to-paper');
      final stream = doc.resolve(doc.pages[1]['Contents']) as PdfStream;
      expect(inflate(stream.raw).length, greaterThan(1000));
      // A stream of nonsense comes back empty rather than throwing, so a
      // damaged page arrives as a display list with nothing in it. That is
      // what lets a damaged document be a designed state upstream instead of
      // an exception crossing the render path.
      expect(inflate(Uint8List.fromList([1, 2, 3])), isEmpty);
      expect(inflate(Uint8List(0)), isEmpty);
    });
  });

  // ----------------------------------------------- what producers write

  group('what other producers write', () {
    TextRunCmd spaced(String text, double x, {required double space}) =>
        TextRunCmd(
          text: text,
          x: x,
          y: 100,
          fontSize: 10,
          widthPts: 30,
          fontKey: 'F1',
          bold: false,
          italic: false,
          serif: false,
          mono: false,
          color: 0xFF000000,
          rotated: false,
          seq: 0,
          spaceWidthPts: space,
        );

    Uint8List withFont(String content, String font, List<List<int>> extra) =>
        buildPdf([
          obj('<< /Type /Catalog /Pages 2 0 R >>'),
          obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
          obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
              '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>'),
          streamObj('', ascii.encode(content)),
          obj(font),
          ...extra,
        ]);

    final inter = File('assets/fonts/Inter-Regular.ttf').readAsBytesSync();
    final interFont = TrueTypeFont.parse(inter);

    test('a type size carried by the text matrix still gives runs their width',
        () {
      // Quartz, Cairo and others set the font at 1 and scale the text matrix
      // to the real size, one glyph at a time.
      final doc = PdfFile.open(onePage(
        'BT /F1 1 Tf 12 0 0 12 10 100 Tm (Mon) Tj (itoring) Tj ET',
        resources: kHelveticaRes,
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      // Mon in Helvetica is M+o+n = 1945/1000 em.
      expect(dl.texts.first.widthPts, closeTo(1.945 * 12, 0.05));
      expect(dl.texts.first.fontSize, closeTo(12, 1e-9));
      expect(mergeRuns(dl.texts).single.text, 'Monitoring',
          reason: 'a run measured at 1pt leaves a false gap and splits words');
    });

    test('a Type3 font is measured through its own font matrix', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 10 Tf 10 100 Td (AA) Tj ET',
        resources: '/Font << /F1 << /Type /Font /Subtype /Type3 '
            '/FontMatrix [0.01 0 0 0.01 0 0] /FontBBox [0 0 80 100] '
            '/FirstChar 65 /LastChar 65 /Widths [50] '
            '/Encoding << /Differences [65 /A] >> /CharProcs << >> >> >>',
      ));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      expect(run.text, 'AA');
      // 50 glyph units at 0.01 is half an em, twice, at 10pt.
      expect(run.widthPts, closeTo(10, 1e-9));
      expect(run.fontSize, closeTo(10, 1e-9));
    });

    test('turned text keeps its angle and joins along its own baseline', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 12 Tf 0 1 -1 0 100 50 Tm (U) Tj (P) Tj ET',
        resources: kHelveticaRes,
      ));
      final dl = ContentInterpreter(doc).run(doc.pages[0]);
      expect(dl.texts.every((t) => t.rotated), isTrue);
      final line = mergeRuns(dl.texts).single;
      expect(line.text, 'UP');
      expect(line.angle, closeTo(-math.pi / 2, 1e-9));
      expect(line.x, closeTo(100, 1e-9));
      expect(line.y, closeTo(150, 1e-9));
      expect(line.width, closeTo((0.722 + 0.667) * 12, 0.05));
      // Running up the page, the line's box is tall and narrow.
      expect(line.bounds.height, greaterThan(line.bounds.width));
    });

    test('a slanted text matrix is an italic at its upright size', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 12 Tf 1 0 0.3 1 10 100 Tm (Lean) Tj ET',
        resources: kHelveticaRes,
      ));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      expect(run.italic, isTrue);
      expect(run.rotated, isFalse);
      expect(run.fontSize, closeTo(12, 1e-9));
    });

    test('a matrix measures its axes along themselves', () {
      const turned = Mat(0, 1, -1, 0, 0, 0);
      expect(turned.scaleX, 1);
      expect(turned.scaleY, 1);
      const slant = Mat(2, 0, 1, 3, 0, 0);
      expect(slant.scaleX, 2);
      expect(slant.heightY, closeTo(3, 1e-9));
      expect(slant.slanted, isTrue);
      expect(const Mat(2, 0, 0, 3, 0, 0).slanted, isFalse);
    });

    test('an embedded CMap cuts codes by its codespace and maps them to CIDs',
        () {
      final cmap = ascii.encode(
          '1 begincodespacerange <00> <7F> <8000> <FFFF> endcodespacerange\n'
          '1 begincidrange <41> <5A> 1 endcidrange\n'
          '1 begincidchar <8001> 40 endcidchar\n');
      final doc = PdfFile.open(withFont(
        'BT /F1 10 Tf 10 100 Td <41428001> Tj ET',
        '<< /Type /Font /Subtype /Type0 /BaseFont /Mixed /Encoding 6 0 R '
            '/DescendantFonts [7 0 R] >>',
        [
          streamObj('/Type /CMap', cmap),
          obj('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Mixed '
              '/DW 900 /W [1 [600 700]] >>'),
        ],
      ));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      expect(run.text, 'AB');
      // A and B are one byte each and CIDs 1 and 2; <8001> is CID 40, which
      // takes the default width.
      expect(run.widthPts, closeTo((600 + 700 + 900) / 100, 1e-9));
    });

    test('a Unicode CMap reads its codes as the text', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 10 Tf 10 100 Td <4E2D6587> Tj ET',
        resources: '/Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont '
            '/Song /Encoding /UniGB-UCS2-H /DescendantFonts [<< /Type /Font '
            '/Subtype /CIDFontType0 /BaseFont /Song /DW 1000 >>] >> >>',
      ));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      expect(run.text, '中文');
      expect(run.widthPts, closeTo(20, 1e-9));
    });

    test('vertical writing sets each glyph below the last', () {
      final doc = PdfFile.open(onePage(
        'BT /F1 10 Tf 50 100 Td <00410042> Tj ET',
        resources: '/Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont '
            '/Tate /Encoding /Identity-V /DescendantFonts [<< /Type /Font '
            '/Subtype /CIDFontType2 /BaseFont /Tate /DW 1000 >>] >> >>',
      ));
      final texts = ContentInterpreter(doc).run(doc.pages[0]).texts;
      expect(texts.map((t) => t.text).toList(), ['A', 'B']);
      expect(texts[1].y - texts[0].y, closeTo(10, 1e-9));
      expect(texts[0].x, closeTo(45, 1e-9),
          reason: 'a vertical glyph hangs centred on the pen');
    });

    test('a composite font with no ToUnicode is read through its own cmap',
        () {
      String hex(int gid) => gid.toRadixString(16).padLeft(4, '0');
      final h = interFont.glyphFor('H'.codeUnitAt(0));
      final i = interFont.glyphFor('i'.codeUnitAt(0));
      final doc = PdfFile.open(withFont(
        'BT /F1 10 Tf 10 100 Td <${hex(h)}${hex(i)}> Tj ET',
        '<< /Type /Font /Subtype /Type0 /BaseFont /Inter '
            '/Encoding /Identity-H /DescendantFonts [6 0 R] >>',
        [
          obj('<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Inter '
              '/CIDToGIDMap /Identity /FontDescriptor 7 0 R >>'),
          obj('<< /Type /FontDescriptor /FontName /Inter /Flags 32 '
              '/FontFile2 8 0 R >>'),
          streamObj('', inter),
        ],
      ));
      expect(ContentInterpreter(doc).run(doc.pages[0]).texts.single.text,
          'Hi');
    });

    test('a font with no /Widths is measured from the font it embeds', () {
      final doc = PdfFile.open(withFont(
        'BT /F1 10 Tf 10 100 Td (AW) Tj ET',
        '<< /Type /Font /Subtype /TrueType /BaseFont /Inter '
            '/FontDescriptor 6 0 R >>',
        [
          obj('<< /Type /FontDescriptor /FontName /Inter /Flags 32 '
              '/FontFile2 7 0 R >>'),
          streamObj('', inter),
        ],
      ));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      final a = interFont.widthOf(interFont.glyphFor(0x41));
      final w = interFont.widthOf(interFont.glyphFor(0x57));
      expect(run.widthPts, closeTo((a + w) / 100, 1e-9));
      expect(run.widthPts, isNot(closeTo((667 + 944) / 100, 0.05)),
          reason: 'not Helvetica, which is what it fell back to before');
    });

    test('the word gap scales with the width of the font\'s own space', () {
      // Half a point apart at 10pt: a break in a Helvetica-like face, and
      // only kerning in a monospace one whose space is 0.6em.
      final plain = mergeRuns([
        spaced('foo', 0, space: 2.78),
        spaced('bar', 30.5, space: 2.78),
      ]);
      expect(plain.single.text, 'foo bar');
      final mono = mergeRuns([
        spaced('foo', 0, space: 6),
        spaced('bar', 30.5, space: 6),
      ]);
      expect(mono.single.text, 'foobar');
      final unknown = mergeRuns([
        spaced('foo', 0, space: 0),
        spaced('bar', 30.5, space: 0),
      ]);
      expect(unknown.single.text, 'foo bar',
          reason: 'a font with no space keeps the tuned threshold');
    });

    test('the space width reaches the runs the page emits', () {
      final doc = PdfFile.open(
          onePage('BT /F1 10 Tf 10 100 Td (a b) Tj ET', resources: kHelveticaRes));
      final run = ContentInterpreter(doc).run(doc.pages[0]).texts.single;
      expect(run.spaceWidthPts, closeTo(2.78, 1e-9));
    });

    test('the file says which program wrote it', () {
      Uint8List withInfo(String info) => buildPdf([
            obj('<< /Type /Catalog /Pages 2 0 R >>'),
            obj('<< /Type /Pages /Kids [] /Count 0 >>'),
            obj(info),
          ], trailerExtra: '/Info 3 0 R ');
      expect(PdfFile.open(withInfo('<< /Producer (iOS Version 16.7.11) >>'))
          .producer, 'iOS Version 16.7.11');
      expect(PdfFile.open(withInfo('<< /Producer <FEFF00690054006500780074> >>'))
          .producer, 'iText');
      expect(PdfFile.open(withInfo('<< >>')).producer, '');
    });
  });

  // -------------------------------------------------------------- painting

  group('painting a page', () {
    /// Paints [list] at one point per pixel and reads the colour at (x, y).
    Future<int> pixelAt(WidgetTester tester, PageDisplayList list, int x, int y,
        {List<LaidOutRun> runs = const []}) async {
      var argb = 0;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        PageListPainter(
          list: list,
          runs: runs,
          images: const {},
          serifFamily: 'Inter',
          sansFamily: 'Inter',
        ).paint(ui.Canvas(recorder),
            ui.Size(list.widthPts, list.heightPts));
        final image = await recorder
            .endRecording()
            .toImage(list.widthPts.round(), list.heightPts.round());
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final at = (y * list.widthPts.round() + x) * 4;
        final b = data!.buffer.asUint8List();
        argb = (b[at + 3] << 24) | (b[at] << 16) | (b[at + 1] << 8) | b[at + 2];
        image.dispose();
      });
      return argb;
    }

    PathCmd box(double l, double t, double r, double b, int colour, int seq) =>
        PathCmd(
          segs: [
            PathSeg(PathOp.move, [l, t]),
            PathSeg(PathOp.line, [r, t]),
            PathSeg(PathOp.line, [r, b]),
            PathSeg(PathOp.line, [l, b]),
            const PathSeg(PathOp.close, []),
          ],
          fill: true,
          stroke: false,
          fillColor: colour,
          strokeColor: 0xFF000000,
          lineWidth: 1,
          evenOdd: false,
          seq: seq,
        );

    testWidgets('the later command in the content stream lands on top',
        (WidgetTester tester) async {
      final under = PageDisplayList(widthPts: 40, heightPts: 40, rotation: 0);
      under.paths
        ..add(box(0, 0, 40, 40, 0xFFFF0000, 0))
        ..add(box(0, 0, 20, 20, 0xFF0000FF, 5));
      expect(await pixelAt(tester, under, 10, 10), 0xFF0000FF);
      expect(await pixelAt(tester, under, 30, 30), 0xFFFF0000);

      // The same two commands with their order in the stream swapped. Three
      // parallel passes would paint these identically, which is the bug the
      // seq ordering exists to prevent.
      final over = PageDisplayList(widthPts: 40, heightPts: 40, rotation: 0);
      over.paths
        ..add(box(0, 0, 40, 40, 0xFFFF0000, 5))
        ..add(box(0, 0, 20, 20, 0xFF0000FF, 0));
      expect(await pixelAt(tester, over, 10, 10), 0xFFFF0000);
    });

    testWidgets('a half transparent fill really is half transparent',
        (WidgetTester tester) async {
      final list = PageDisplayList(widthPts: 20, heightPts: 20, rotation: 0);
      list.paths.add(box(0, 0, 20, 20, 0x80FF0000, 0));
      final pixel = await pixelAt(tester, list, 10, 10);
      // Red at half alpha over the page's white ground.
      expect((pixel >> 24) & 0xFF, 0xFF);
      expect((pixel >> 16) & 0xFF, 0xFF);
      expect((pixel >> 8) & 0xFF, inInclusiveRange(126, 129));
      expect(pixel & 0xFF, inInclusiveRange(126, 129));
    });

    testWidgets('a turned line is painted along its own baseline',
        (WidgetTester tester) async {
      final list = PageDisplayList(widthPts: 60, heightPts: 120, rotation: 0);
      final run = LaidOutRun(
          'WWWWWW', 20, 10, 10, 60, 0, 0xFF000000, 0, angle: math.pi / 2);
      late ui.Rect inked;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        PageListPainter(
          list: list,
          runs: [run],
          images: const {},
          serifFamily: 'Inter',
          sansFamily: 'Inter',
        ).paint(ui.Canvas(recorder), const ui.Size(60, 120));
        final image = await recorder.endRecording().toImage(60, 120);
        final b = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        var l = 60, t = 120, r = 0, bottom = 0;
        for (var y = 0; y < 120; y++) {
          for (var x = 0; x < 60; x++) {
            if (b[(y * 60 + x) * 4] < 128) {
              l = math.min(l, x);
              t = math.min(t, y);
              r = math.max(r, x);
              bottom = math.max(bottom, y);
            }
          }
        }
        inked = ui.Rect.fromLTRB(l.toDouble(), t.toDouble(), r.toDouble(),
            bottom.toDouble());
        image.dispose();
      });
      expect(inked.height, greaterThan(inked.width * 3),
          reason: 'drawn flat, six Ws would run across the page');
      expect(inked.left, greaterThanOrEqualTo(19),
          reason: 'turned clockwise, the letters stand to the right of it');
    });

    test('a line the file spreads wide is letter spaced to fill it', () {
      final r = LaidOutRun('SLIDE', 0, 100, 10, 200, 0, 0xFF000000, 0);
      final set = setRun(r, serifFamily: 'Inter', sansFamily: 'Inter');
      expect(set.width, closeTo(200, 1));
      expect(runSqueeze(r, set), closeTo(1, 0.01));
    });

    test('a line far too long for its width is squeezed only so far', () {
      final r = LaidOutRun('squeezed', 0, 100, 10, 5, 0, 0xFF000000, 0);
      final set = setRun(r, serifFamily: 'Inter', sansFamily: 'Inter');
      expect(runSqueeze(r, set), kSqueezeMin);
    });

    testWidgets('an unpainted page is white, never transparent',
        (WidgetTester tester) async {
      final list = PageDisplayList(widthPts: 20, heightPts: 20, rotation: 0);
      expect(await pixelAt(tester, list, 10, 10), 0xFFFFFFFF);
    });

    test('the painter repaints only when what it was given changes', () {
      final list = PageDisplayList(widthPts: 20, heightPts: 20, rotation: 0);
      final runs = mergeRuns([run('a', 0, 10)]);
      PageListPainter painter(List<LaidOutRun> r) => PageListPainter(
            list: list,
            runs: r,
            images: const {},
            serifFamily: 'Inter',
            sansFamily: 'Inter',
          );
      expect(painter(runs).shouldRepaint(painter(runs)), isFalse);
      expect(painter(runs).shouldRepaint(painter(mergeRuns([run('b', 0, 10)]))),
          isTrue);
    });
  });

  // --------------------------------------------------------------- search

  group('search', () {
    PdfSearch indexOf(String name) {
      final doc = bundled(name);
      final search = PdfSearch(doc.pageCount);
      for (var p = 0; p < doc.pageCount; p++) {
        search.addDisplayList(p, ContentInterpreter(doc).run(doc.pages[p]));
      }
      return search;
    }

    test('an index covers every page and counts pages as its unit', () {
      final search = indexOf('field-guide-to-paper');
      expect(search.unitCount, 6);
      expect(search.indexedPages.toSet(), {0, 1, 2, 3, 4, 5});
      expect(search.hasPage(5), isTrue);
      expect(search.hasPage(6), isFalse);
      expect(search.runsOf(6), isEmpty);
      expect(search.textOf(0), startsWith('A Field Guide to Paper'));
    });

    test('a query is case insensitive and reports where every hit sits', () {
      final search = indexOf('field-guide-to-paper');
      final hits = search.search('GRAIN');
      expect(hits.length, greaterThan(8));
      expect(hits.map((h) => h.page).toSet(), contains(4));
      for (final h in hits) {
        expect(h.end - h.start, 5);
        expect(search.runsOf(h.page)[h.runIndex]
            .text
            .substring(h.start, h.end)
            .toLowerCase(),
            'grain');
        expect(h.rect.left, greaterThanOrEqualTo(0));
        expect(h.rect.right, lessThanOrEqualTo(612));
        expect(h.rect.top, greaterThanOrEqualTo(0));
        expect(h.rect.bottom, lessThanOrEqualTo(792));
        expect(h.rect.width, greaterThan(0));
        expect(h.snippet.toLowerCase(), contains('grain'));
        expect(h.snippet.substring(h.snippetStart, h.snippetStart + 5)
            .toLowerCase(),
            'grain');
      }
    });

    test('hits arrive in reading order and their positions do not go back', () {
      final search = indexOf('press-lease');
      final hits = search.search('lessee');
      expect(hits.length, greaterThan(10));
      var previous = -1.0;
      for (final h in hits) {
        final at = search.positionOf(h);
        expect(at, greaterThanOrEqualTo(previous));
        expect(at, inInclusiveRange(0, 1));
        previous = at;
      }
      expect(search.positionOf(hits.first), lessThan(0.5));
      expect(search.positionOf(hits.last), greaterThan(0.5));
    });

    test('a query that is not there finds nothing, and nor does an empty one',
        () {
      final search = indexOf('press-lease');
      expect(search.search('linotype'), isEmpty);
      expect(search.search(''), isEmpty);
      expect(search.search('   '), isEmpty);
      expect(search.countOf('press'), greaterThan(0));
    });

    test('repeated matches inside one line are all found', () {
      final search = PdfSearch(1)
        ..setPage(0, mergeRuns([run('a rag rag rag sheet', 0, 100, width: 90)]));
      final hits = search.searchPage(0, 'rag');
      expect(hits.map((h) => h.start).toList(), [2, 6, 10]);
      expect(hits[0].rect.left, lessThan(hits[1].rect.left));
      expect(hits[2].rect.right, lessThan(90));
    });

    test('an index can be built straight from a list of display lists', () {
      final doc = bundled('press-lease');
      final search = PdfSearch.fromDisplayLists([
        for (var p = 0; p < doc.pageCount; p++)
          ContentInterpreter(doc).run(doc.pages[p]),
      ]);
      expect(search.unitCount, 2);
      expect(search.search('Equipment').length, greaterThan(5));
    });
  });
}

// ------------------------------------------------------------ image fixtures

/// A one page file holding a 3 x 1 indexed image at 8 bits per component.
Uint8List indexedEightBit() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 3 /Height 1 '
          '/BitsPerComponent 8 '
          '/ColorSpace [/Indexed /DeviceRGB 2 <FF000000FF000000FF>]',
          [0, 1, 2]),
    ]);

/// The same image at 4 bits per component, so a row needs unpacking.
Uint8List indexedFourBit() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 3 /Height 1 '
          '/BitsPerComponent 4 '
          '/ColorSpace [/Indexed /DeviceRGB 1 <FF000000FF00>]',
          [0x01, 0x00]),
    ]);

/// A 3 x 1 DeviceCMYK image: cyan, black, white.
Uint8List cmykImage() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 3 /Height 1 '
          '/BitsPerComponent 8 /ColorSpace /DeviceCMYK',
          [255, 0, 0, 0, 0, 0, 0, 255, 0, 0, 0, 0]),
    ]);

/// A 2 x 1 image whose colour space is an ICC profile with three components.
Uint8List iccImage() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 2 /Height 1 '
          '/BitsPerComponent 8 /ColorSpace [/ICCBased 6 0 R]',
          [1, 2, 3, 4, 5, 6]),
      streamObj('/N 3', [0]),
    ]);

/// A 2 x 1 image in an encoding this reader does not decode.
Uint8List jpxImage() => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 2 /Height 1 '
          '/BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /JPXDecode',
          [0, 1, 2, 3]),
    ]);

/// A 10 x 2 one bit grey image: an alternating row over a solid one.
Uint8List bilevelImage({String extra = ''}) => buildPdf([
      obj('<< /Type /Catalog /Pages 2 0 R >>'),
      obj('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
      obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] '
          '/Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>'),
      streamObj('', ascii.encode('q 100 0 0 100 10 10 cm /Im0 Do Q')),
      streamObj(
          '/Type /XObject /Subtype /Image /Width 10 /Height 2 '
          '/BitsPerComponent 1 /ColorSpace /DeviceGray $extra',
          [0xAA, 0x80, 0xFF, 0xC0]),
    ]);
