import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/screens/desk/overflow_menu.dart';
import 'package:quire/services/document_store.dart';

import 'sign_test.dart' show scriptStrokes;
import 'support/fixtures.dart';
import 'dart:convert';

/// The fills a page paints in the signature's ink colour.
int _inkFills(Uint8List bytes, int page) {
  final file = PdfFile.open(bytes);
  final list = ContentInterpreter(file).run(file.pages[page]);
  return list.paths.where((p) => p.fill && p.fillColor == 0xFF111111).length;
}

PlacedSignature _drawn({int page = 0}) => PlacedSignature(
  pageIndex: page,
  rect: const Rect.fromLTWH(200, 300, 200, 80),
  strokes: SignatureMark.of(scriptStrokes()).outlines,
);

void main() {
  group('the signed copy that gets shared', () {
    for (final name in <String>[kPressLease, kFieldGuide]) {
      test('carries the ink when $name is read back', () async {
        final store = await storeFor(name);
        final before = _inkFills(await documentBytes(name), 0);
        store.placeSignature(_drawn());

        final bytes = store.signedPdf(
          pictures: await store.signaturePictures(),
        )!;

        expect(_inkFills(bytes, 0), greaterThan(before));
        // The original is untouched, only added to.
        final original = await documentBytes(name);
        expect(bytes.sublist(0, original.length), original);
      });
    }

    test('a mark with no ink is refused rather than shared blank', () async {
      final store = await storeFor(kPressLease);
      store.placeSignature(
        const PlacedSignature(
          pageIndex: 0,
          rect: Rect.fromLTWH(200, 300, 200, 80),
          strokes: <List<Offset>>[],
        ),
      );
      expect(store.signedPdf, throwsA(isA<PdfWriteError>()));
    });
  });

  group('sharing a signed PDF from the desk', () {
    final entry = entryFor(kPressLease);

    bool offers(DeskAction action, {required bool signed}) => action.suits(
      entry,
      starred: false,
      binned: false,
      signed: signed,
      canCopy: true,
    );

    test('has no second share row that could send the unsigned file', () {
      expect(offers(DeskAction.shareOriginal, signed: true), isTrue);
      expect(offers(DeskAction.shareUnsigned, signed: true), isTrue);
      expect(DeskAction.shareUnsigned.label, contains('unsigned'));
    });

    test('offers no unsigned row for a document nobody signed', () {
      expect(offers(DeskAction.shareUnsigned, signed: false), isFalse);
      expect(offers(DeskAction.shareOriginal, signed: false), isTrue);
    });
  });

  group('a file whose page holds true and false', () {
    test('is still written signed', () {
      final bytes = _pdfWithBooleans();
      final file = PdfFile.open(bytes);
      final signed = PdfSignatureWriter.signed(file, <PlacedInk>[
        PlacedInk(
          pageIndex: 0,
          rect: const Rect.fromLTWH(100, 100, 200, 80),
          outlines: SignatureMark.of(scriptStrokes()).outlines,
        ),
      ]);
      final text = latin1.decode(signed.sublist(bytes.length));
      expect(text, contains('/I true'));
      expect(text, contains('/K false'));
      expect(_inkFills(signed, 0), greaterThan(0));
    });
  });
}

/// A one page PDF whose page dictionary carries booleans, the way a page with
/// a transparency group does, with its cross reference worked out byte by byte.
Uint8List _pdfWithBooleans() {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Group << /S /Transparency /CS /DeviceRGB /I true /K false >> '
        '/Contents 4 0 R /Resources << >> >>',
    '<< /Length 11 >>\nstream\n0 0 m 1 1 l\nendstream',
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
