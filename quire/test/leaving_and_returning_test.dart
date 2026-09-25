import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/pdf/writer.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/incoming_documents.dart';

import 'sign_test.dart' show scriptStrokes;
import 'support/fixtures.dart';

void main() {
  group('a document handed in by another app', () {
    test('is called by its own name, not the copy stamp', () {
      const document = IncomingDocument(
        path: '/data/cache/incoming/1726500000123_lease.pdf',
        format: DocFormat.pdf,
      );
      expect(document.name, 'lease.pdf');
      expect(LibraryEntry.titleFor(document.name), 'Lease');
    });

    test('keeps a name that only starts with a number', () {
      const document = IncomingDocument(
        path: '/data/cache/2026_budget.xlsx',
        format: DocFormat.xlsx,
      );
      expect(document.name, '2026_budget.xlsx');
    });

    test('handed in again is the card already on the desk', () async {
      final folder = await Directory.systemTemp.createTemp('quire_holding');
      addTearDown(() => folder.delete(recursive: true));
      final bytes = await documentBytes(kPressLease);
      final kept = File('${folder.path}/1726500000123_lease.pdf');
      await kept.writeAsBytes(bytes);
      final entry = LibraryEntry(
        path: kept.path,
        title: 'Lease',
        format: DocFormat.pdf,
        bytes: bytes.length,
        source: DocSource.file,
      );
      final library = LibraryStore(entries: <LibraryEntry>[entry]);
      addTearDown(library.dispose);

      final again = await library.importFile('lease.pdf', bytes);
      expect(again, same(entry));
      expect(library.entries.length, 1);
    });
  });

  group('a signed document that wants its password', () {
    test('says so rather than that nothing is signed', () async {
      final bytes = await documentBytes('press-lease-locked.pdf');
      const entry = LibraryEntry(
        path: 'assets/documents/press-lease-locked.pdf',
        title: 'Press Lease Locked',
        format: DocFormat.pdf,
        bytes: 0,
        source: DocSource.asset,
      );
      final store = DocumentStore.ready(entry, bytes);
      expect(store.locked, isNotNull);
      store.placeSignature(
        PlacedSignature(
          pageIndex: 0,
          rect: const Rect.fromLTWH(200, 300, 200, 80),
          strokes: SignatureMark.of(scriptStrokes()).outlines,
        ),
      );
      final library = LibraryStore(entries: <LibraryEntry>[entry]);
      addTearDown(library.dispose);
      library.storeFor(entry).restore(store.toJson());

      await expectLater(
        library.exportSigned(entry),
        throwsA(
          isA<PdfWriteError>().having(
            (e) => e.message,
            'message',
            contains('password'),
          ),
        ),
      );
    });
  });

  group('a signature used just before leaving', () {
    test('is written without waiting for the usual quiet', () async {
      final library = LibraryStore();
      addTearDown(library.dispose);
      // With nowhere to write, saving now must still be safe to call on the
      // way out.
      await library.saveNow();
    });
  });
}
