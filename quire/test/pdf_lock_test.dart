/// Putting a password on a document from inside the app: who is offered it,
/// what the sheet asks for, and what comes out the other end.
///
/// `pdf_seal_test.dart` proves the bytes. This proves the half a reader
/// touches, and it finishes by taking the file the flow actually wrote and
/// handing it back to quire's own reader, because a sheet that collected a
/// password and wrote something unopenable would pass every other test here.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/seal_sheet.dart';
import 'package:quire/services/document_store.dart';

import 'pdf_seal_test.dart' show allText, kPassword;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// The bundled file another tool locked, which quire can see and cannot read.
const String kLockedLease = 'press-lease-locked.pdf';

/// The bundled file carrying an owner password and no reader password. It
/// opens with nothing asked, and it is still an encrypted file.
const String kOwnedLease = 'press-lease-owner.pdf';

/// share_plus names its own channel. It is written out here because the test
/// has to stand in for the phone at the same door the plugin knocks on, and
/// the plugin's constant is not this package's to depend on.
const MethodChannel kShareChannel = MethodChannel(
  'dev.fluttercommunity.plus/share',
);

void main() {
  group('the offer to protect a document', () {
    testWidgets('is made for a page file', (tester) async {
      await _openMenuOver(tester, await storeFor(kFieldGuide));
      expect(find.text(kSealTitle), findsOneWidget);
    });

    // A workbook, a deck and prose, each in a test of its own: two documents
    // opened one after the other in one test share the reader's own state,
    // and a menu left standing from the first would swallow the press that
    // was meant to open the second.
    for (final name in <String>[
      kPressRunCosts,
      kPressDayBriefing,
      kHouseStyle,
    ]) {
      testWidgets('is not made for $name', (tester) async {
        await _openMenuOver(tester, await storeFor(name));
        expect(find.text(kSealTitle), findsNothing);
      });
    }

    testWidgets('is not made for a document somebody else locked', (
      tester,
    ) async {
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        await documentBytes(kLockedLease),
      );
      expect(store.locked, isNotNull);
      await _openMenuOver(tester, store);
      expect(find.text(kSealTitle), findsNothing);
    });

    testWidgets('is not made for one that opened on an owner password', (
      tester,
    ) async {
      // Nothing about this file looks locked: it opens with no password
      // asked for. A second handler on top of the first would leave a file
      // with neither, so the row has to be missing from a document that reads
      // perfectly well.
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        await documentBytes(kOwnedLease),
      );
      expect(store.locked, isNull);
      expect(store.pdf?.encrypted, isTrue);
      await _openMenuOver(tester, store);
      expect(find.text(kSealTitle), findsNothing);
    });

    testWidgets('sits with the other things that make a new file', (
      tester,
    ) async {
      await _openMenuOver(tester, await storeFor(kFieldGuide));
      double at(String label) => tester.getCenter(find.text(label)).dy;

      // The pills run down from the dots in the order the reader lists them,
      // so this is the order of the menu itself: what this document can be
      // turned into, and then what can be done with the reading of it.
      expect(at('Sign this page'), lessThan(at(kSealTitle)));
      expect(at(kSealTitle), lessThan(at('Dog ear this page')));
    });
  });

  group('the sheet that takes the password', () {
    testWidgets('says what quire will not do with it, and what it is worth', (
      tester,
    ) async {
      await _openSheet(tester, await storeFor(kPressLease));
      expect(find.byType(SealSheet), findsOneWidget);
      expect(find.text(kSealPromise), findsOneWidget);
      expect(find.text(kSealStrength), findsOneWidget);
    });

    testWidgets('turns down two that differ, on the sheet, and then takes '
        'two that agree', (tester) async {
      await _openSheet(tester, await storeFor(kPressLease));

      await tester.enterText(_fields().at(0), 'the long way');
      await tester.enterText(_fields().at(1), 'the long wya');
      await tester.pump();
      await tester.tap(find.text('Protect a copy'));
      await settle(tester);

      // Still here, and saying so itself. Nothing was put over the top of it.
      expect(find.byType(SealSheet), findsOneWidget);
      expect(find.text(kSealMismatch), findsOneWidget);
      expect(find.text(kSealPromise), findsNothing);

      await tester.enterText(_fields().at(1), 'the long way');
      await tester.pump();
      // The finding goes as soon as the second one is touched again.
      expect(find.text(kSealMismatch), findsNothing);
      await tester.tap(find.text('Protect a copy'));
      await settle(tester);
      expect(find.byType(SealSheet), findsNothing);
    });

    testWidgets('offers nothing to press until both have been typed', (
      tester,
    ) async {
      await _openSheet(tester, await storeFor(kPressLease));
      await tester.tap(find.text('Protect a copy'));
      await settle(tester);
      expect(find.byType(SealSheet), findsOneWidget);

      await tester.enterText(_fields().at(0), 'one side only');
      await tester.pump();
      await tester.tap(find.text('Protect a copy'));
      await settle(tester);
      expect(find.byType(SealSheet), findsOneWidget);
    });
  });

  group('the copy the flow writes', () {
    testWidgets('is refused without the password and opens with it', (
      tester,
    ) async {
      final desk = _exportingDesk(tester);
      final entry = entryFor(kPressLease);
      final library = LibraryStore(
        entries: <LibraryEntry>[entry],
        catalogue: desk,
      );
      addTearDown(library.dispose);
      final store = library.storeFor(entry)
        ..loadFrom(await documentBytes(kPressLease));

      await _openSheet(tester, store, library: library);
      await _type(tester, kPassword);
      await settle(tester);

      // Told apart from the original by its name alone, which is all a share
      // sheet gives anybody to go on.
      expect(desk.written.keys, <String>['Press Lease protected.pdf']);
      final sealed = desk.written.values.single;

      expect(() => PdfFile.open(sealed), throwsA(isA<PdfLocked>()));
      expect(
        () => PdfFile.open(sealed, password: 'the grain runs the short way'),
        throwsA(isA<PdfLocked>()),
      );

      final original = PdfFile.open(await documentBytes(kPressLease));
      final opened = PdfFile.open(sealed, password: kPassword);
      expect(opened.pageCount, original.pageCount);
      expect(allText(opened), allText(original));
    });

    testWidgets('leaves the document it was made from alone', (tester) async {
      final desk = _exportingDesk(tester);
      final entry = entryFor(kPressLease);
      final library = LibraryStore(
        entries: <LibraryEntry>[entry],
        catalogue: desk,
      );
      addTearDown(library.dispose);
      final store = library.storeFor(entry)
        ..loadFrom(await documentBytes(kPressLease));

      await _openSheet(tester, store, library: library);
      await _type(tester, kPassword);
      await settle(tester);

      expect(store.bytes, await documentBytes(kPressLease));
      expect(store.locked, isNull);
    });

    testWidgets('a document that cannot be sealed says why in the band', (
      tester,
    ) async {
      // With no desk behind the reader there is nowhere to write, which is
      // the same shape as any other refusal: a line where the title was, and
      // no dialog anywhere.
      final store = await storeFor(kPressLease);
      await _openSheet(tester, store);
      await _type(tester, kPassword);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final band = tester.widget<ReaderChrome>(find.byType(ReaderChrome));
      expect(band.notice, 'The protected copy could not be written.');
    });
  });

  group('its golden', () {
    setUp(() {
      // The field is live the moment the sheet arrives, and a blinking caret
      // is a moving part.
      EditableText.debugDeterministicCursor = true;
      addTearDown(() => EditableText.debugDeterministicCursor = false);
    });

    testWidgets('reader__seal', (tester) async {
      await _openSheet(tester, await storeFor(kPressLease));
      await capture(tester, 'reader__seal');
    });
  });
}

/// The reader, assembled the way the app assembles it.
Widget _host(DocumentStore store, {LibraryStore? library}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store, library: library),
);

/// The band's three dots, which is what the reader's menu comes out of.
final Finder _dots = find.bySemanticsLabel(
  'What can be done with this document',
);

/// Opens [store] in the reader and brings its menu out.
Future<void> _openMenuOver(
  WidgetTester tester,
  DocumentStore store, {
  LibraryStore? library,
}) async {
  await pumpScreen(tester, _host(store, library: library));
  await settle(tester);
  await tester.tap(_dots);
  await settle(tester);
}

/// Opens [store] in the reader and goes as far as the sheet.
Future<void> _openSheet(
  WidgetTester tester,
  DocumentStore store, {
  LibraryStore? library,
}) async {
  await _openMenuOver(tester, store, library: library);
  await tester.tap(find.text(kSealTitle));
  await settle(tester);
}

/// The two fields on the sheet, in the order they are read down.
Finder _fields() => find.descendant(
  of: find.byType(SealSheet),
  matching: find.byType(EditableText),
);

/// Types [password] into both fields and presses the pill.
Future<void> _type(WidgetTester tester, String password) async {
  await tester.enterText(_fields().at(0), password);
  await tester.enterText(_fields().at(1), password);
  await tester.pump();
  await tester.tap(find.text('Protect a copy'));
}

/// A desk that writes its exports into a folder of its own and remembers
/// what went into them, standing in for the phone's storage and its share
/// sheet both.
_ExportingDesk _exportingDesk(WidgetTester tester) {
  // Every touch of the disk here is synchronous. A widget test runs on a
  // clock it winds itself, and an awaited file operation completes on the
  // real one, which is a wait that never ends.
  final folder = Directory.systemTemp.createTempSync('quire_sealed');
  addTearDown(() => folder.deleteSync(recursive: true));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    kShareChannel,
    (call) async => 'dev.fluttercommunity.plus/share/unavailable',
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      kShareChannel,
      null,
    ),
  );
  return _ExportingDesk(folder);
}

class _ExportingDesk extends SavedDesk {
  _ExportingDesk(this.folder);

  final Directory folder;

  /// Every export written, by the name it was written under.
  final Map<String, Uint8List> written = <String, Uint8List>{};

  @override
  Future<File> writeExport(String name, Uint8List bytes) async {
    written[name] = bytes;
    final file = File('${folder.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }
}
