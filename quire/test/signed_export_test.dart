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
}
