import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/failure_log.dart';
import 'package:quire/services/library_catalogue.dart';
import 'package:quire/widgets/damaged_surface.dart';

import 'support/golden.dart';

/// Where a failure goes, and what the reader is shown where the broken thing
/// was.
void main() {
  setUp(failures.clear);

  group('the parse boundary', () {
    test('an error no parser meant to throw comes back as a damaged file', () {
      // A shared string index of minus five. The parser reaches for it with a
      // guard that only checks the top end, so the list is indexed from the
      // wrong direction and raises a RangeError, which is an Error and not an
      // Exception: the boundary used to name the two exceptions it expected
      // and let this one past.
      final loaded = DocumentLoader.load(
        bookWithCells('<c r="A1" t="s"><v>-5</v></c>'),
        'ledger.xlsx',
      );

      expect(loaded.failed, isTrue);
      expect(loaded.error, isA<RangeError>());
      expect(loaded.format, 'xlsx');
      // The bytes are kept, which is what lets the reader try again.
      expect(loaded.bytes, isNotEmpty);
    });

    test('a file it can read is still read', () {
      final loaded = DocumentLoader.load(
        bookWithCells('<c r="A1" t="str"><v>Laid</v></c>'),
        'stock.xlsx',
      );

      expect(loaded.failed, isFalse);
      expect(loaded.document, isNotNull);
    });
  });

  group('a store handed something it cannot read', () {
    test('ends in the failed state and keeps the bytes it was given', () {
      final bytes = bookWithCells('<c r="A1" t="s"><v>-5</v></c>');
      final store = DocumentStore(
        const LibraryEntry(
          path: 'ledger.xlsx',
          title: 'Ledger',
          format: DocFormat.xlsx,
          bytes: 0,
          source: DocSource.file,
        ),
      );

      store.loadFrom(bytes);

      expect(store.state, ParseState.failed);
      expect(store.error, isA<RangeError>());
      expect(store.bytes, isNotEmpty);
    });
  });

  group('a desk the phone will not tell us about', () {
    test('boots anyway, with the shipped documents on it', () async {
      final library = LibraryStore(catalogue: _RefusingCatalogue());

      await library.boot(parse: false);

      expect(library.booted, isTrue);
      expect(library.entries, isNotEmpty);
      expect(failures.count, 1);
      expect(failures.entries.single.where, 'reading the desk');
    });
  });

  group('what stands where a widget would not build', () {
    testWidgets('the app own torn leaf, not a grey rectangle', (tester) async {
      // Put back inside the body rather than in a tear down: the harness
      // checks that a test left this alone, and it checks before tear downs
      // run.
      final was = ErrorWidget.builder;
      ErrorWidget.builder = (details) => const DamagedSurface();
      try {
        await pumpScreen(tester, const _WillNotBuild());
        expect(tester.takeException(), isA<StateError>());

        expect(find.byType(DamagedSurface), findsOneWidget);
        expect(find.text(kSurfaceDamagedLabel), findsOneWidget);
      } finally {
        ErrorWidget.builder = was;
      }
    });

    testWidgets('a slot too small to tear is still not a grey rectangle', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: kDamagedLeast - 1,
              height: kDamagedLeast - 1,
              child: DamagedSurface(),
            ),
          ),
        ),
      );

      expect(find.byType(DamagedSurface), findsOneWidget);
      expect(find.text(kSurfaceDamagedLabel), findsNothing);
    });
  });

  group('the handlers the app installs', () {
    test('every boundary is pointed somewhere', () {
      final wasError = ErrorWidget.builder;
      final wasFlutter = FlutterError.onError;
      final wasPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        ErrorWidget.builder = wasError;
        FlutterError.onError = wasFlutter;
        PlatformDispatcher.instance.onError = wasPlatform;
      });

      installFailureHandlers();

      // What stands in the hole is the app's, not Flutter's.
      expect(
        ErrorWidget.builder(
          FlutterErrorDetails(exception: StateError('no')),
        ),
        isA<DamagedSurface>(),
      );
      // And the platform's own last resort is answered rather than left null,
      // which is what sent an error to a device log and nowhere else.
      expect(PlatformDispatcher.instance.onError, isNotNull);
      final handled = PlatformDispatcher.instance.onError!(
        StateError('from the engine'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(failures.count, 1);
      expect(failures.entries.single.where, 'the platform');
    });
  });

  group('the log itself', () {
    test('keeps the most recent and counts them all', () {
      final log = FailureLog(keep: 3);
      for (var i = 0; i < 10; i++) {
        log.record(StateError('number $i'), where: 'a test');
      }

      expect(log.count, 10);
      expect(log.entries.length, 3);
      expect(log.entries.first.summary, contains('number 7'));
      expect(log.entries.last.ordinal, 10);
    });

    test('an error with nothing to say is still recorded', () {
      final log = FailureLog();
      log.record(null);
      expect(log.count, 1);
      expect(log.entries.single.summary, isNotEmpty);
    });

    test('a stack is kept short enough to read', () {
      final log = FailureLog();
      log.record(StateError('deep'), stack: StackTrace.current);
      final detail = log.entries.single.detail;
      expect(detail, isNotNull);
      expect('\n'.allMatches(detail!).length, lessThan(kFailureFrames));
    });
  });
}

/// A catalogue that cannot read the phone, which is what a withdrawn
/// permission or a file another process is holding looks like from here.
class _RefusingCatalogue extends LibraryCatalogue {
  @override
  Future<List<LibraryEntry>> load() async {
    throw const FileSystemExceptionLike('the desk is unreadable');
  }
}

/// A failure the catalogue could raise, without dragging dart:io into a test
/// that is about what happens next rather than about what went wrong.
class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'FileSystemExceptionLike: $message';
}

/// A widget that throws where a widget is expected to build.
class _WillNotBuild extends StatelessWidget {
  const _WillNotBuild();

  @override
  Widget build(BuildContext context) {
    throw StateError('this one will not build');
  }
}

/// A one sheet workbook whose single row holds [cells].
Uint8List bookWithCells(String cells) {
  final sheet =
      '<?xml version="1.0"?>'
      '<worksheet '
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData><row r="1">$cells</row></sheetData></worksheet>';
  const workbook =
      '<?xml version="1.0"?>'
      '<workbook '
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships">'
      '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';
  const rels =
      '<?xml version="1.0"?>'
      '<Relationships '
      'xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/worksheet" '
      'Target="worksheets/sheet1.xml"/></Relationships>';

  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('xl/workbook.xml', workbook);
  add('xl/_rels/workbook.xml.rels', rels);
  add('xl/worksheets/sheet1.xml', sheet);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
