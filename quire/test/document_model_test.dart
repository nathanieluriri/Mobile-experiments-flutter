import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/format/document_loader.dart';
import 'package:quire/model/document.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/reading_time.dart';

import 'support/fixtures.dart';

void main() {
  group('the loader sniffs by bytes first', () {
    test('every bundled document is recognised', () async {
      final expected = <String, String>{
        kFieldGuide: 'pdf',
        kPressLease: 'pdf',
        kHouseStyle: 'docx',
        kPressRunCosts: 'xlsx',
        kSubscribers: 'csv',
        kBinderyNotes: 'md',
      };
      for (final entry in expected.entries) {
        final bytes = await documentBytes(entry.key);
        expect(DocumentLoader.sniff(bytes, entry.key), entry.value,
            reason: entry.key);
      }
    });

    test('a renamed container is read for what it is, not what it says',
        () async {
      final workbook = await documentBytes(kPressRunCosts);
      expect(DocumentLoader.sniff(workbook, 'not-really.docx'), 'xlsx');

      final word = await documentBytes(kHouseStyle);
      expect(DocumentLoader.sniff(word, 'not-really.xlsx'), 'docx');
    });

    test('a PDF is recognised by its header even without an extension',
        () async {
      final bytes = await documentBytes(kPressLease);
      expect(DocumentLoader.sniff(bytes, 'lease'), 'pdf');
    });

    test('bytes that are nothing at all are unknown', () {
      final garbage =
          Uint8List.fromList(List<int>.generate(64, (i) => (i * 5) % 251));
      expect(DocumentLoader.sniff(garbage, 'mystery.bin'), 'unknown');
    });

    test('a title is the file name, hyphens opened out and capitalised', () {
      expect(DocumentLoader.titleFor('field-guide-to-paper.pdf'),
          'Field Guide To Paper');
      expect(DocumentLoader.titleFor('press_run_costs.xlsx'),
          'Press Run Costs');
      expect(DocumentLoader.titleFor('assets/documents/subscribers.csv'),
          'Subscribers');
    });
  });

  group('every format lands in the shared model', () {
    test('docx is one body section of blocks in document order', () async {
      final doc = await parsedDocument(kHouseStyle);
      expect(doc.sourceFormat, 'docx');
      expect(doc.sections.length, 1);
      expect(doc.sections.single.kind, 'body');
      expect(doc.assets, isNotEmpty, reason: 'the picture travels with it');
      expect(doc.outline, isNotEmpty);
      expect(doc.title, 'House Style');
    });

    test('xlsx is one section per sheet, each a grid', () async {
      final doc = await parsedDocument(kPressRunCosts);
      expect(doc.sourceFormat, 'xlsx');
      expect(doc.sections.map((s) => s.title).toList(),
          <String>['Runs', 'Paper', 'Summary']);
      for (final section in doc.sections) {
        expect(section.kind, 'sheet');
        final grid = section.blocks.single as TableBlock;
        expect(grid.grid, isTrue);
      }
      expect(doc.assets, isEmpty);
    });

    test('csv is one section, one grid, header frozen', () async {
      final doc = await parsedDocument(kSubscribers);
      expect(doc.sourceFormat, 'csv');
      expect(doc.sections.length, 1);
      final grid = doc.sections.single.blocks.single as TableBlock;
      expect(grid.grid, isTrue);
      expect(grid.frozenRows, 1);
      expect(grid.rows.length, 71);
    });

    test('md is one section of blocks with anchored headings', () async {
      final doc = await parsedDocument(kBinderyNotes);
      expect(doc.sourceFormat, 'md');
      expect(doc.sections.length, 1);
      expect(doc.sections.single.kind, 'body');
      for (final heading
          in doc.sections.single.blocks.whereType<HeadingBlock>()) {
        expect(heading.anchor, isNotNull);
      }
    });

    test('a PDF is handed on as bytes, not parsed into blocks', () async {
      final loaded = await loadedDocument(kPressLease);
      expect(loaded.isPdf, isTrue);
      expect(loaded.failed, isFalse);
      expect(loaded.document, isNull);
      expect(loaded.bytes.length, 20966);
    });

    test('word counts are real and stable across two reads', () async {
      final docx = await parsedDocument(kHouseStyle);
      final md = await parsedDocument(kBinderyNotes);
      expect(docx.wordCount, 1565);
      expect(md.wordCount, 1010);
      expect(docx.wordCount, docx.wordCount);
    });

    test('a grid counts the words in its cells', () async {
      final csv = await parsedDocument(kSubscribers);
      expect(csv.wordCount, greaterThan(500));
      final merged = TableBlock(<DocRow>[
        DocRow(<DocCell>[
          const DocCell(<DocBlock>[
            ParagraphBlock(<DocSpan>[DocSpan('two words')])
          ]),
          const DocCell(<DocBlock>[], merged: true),
        ]),
      ], grid: true);
      final doc = QuireDocument(
        title: 'x',
        sections: <DocSection>[
          DocSection('x', <DocBlock>[merged]),
        ],
      );
      expect(doc.wordCount, 2, reason: 'a merged cell is not counted twice');
    });

    test('countWords treats every run of non whitespace as one word', () {
      expect(countWords(''), 0);
      expect(countWords('   '), 0);
      expect(countWords('one'), 1);
      expect(countWords(' one  two\tthree\nfour '), 4);
    });
  });

  group('the failure boundary', () {
    test('garbage bytes fail rather than throw', () {
      final garbage =
          Uint8List.fromList(List<int>.generate(900, (i) => (i * 17) % 251));
      final loaded = DocumentLoader.load(garbage, 'broken.docx');
      expect(loaded.failed, isTrue);
      expect(loaded.document, isNull);
      expect(loaded.error, isNotNull);
    });

    test('a truncated zip fails rather than throws', () async {
      final truncated =
          Uint8List.sublistView(await documentBytes(kHouseStyle), 0, 900);
      final loaded = DocumentLoader.load(truncated, 'house-style.docx');
      expect(loaded.failed, isTrue);
    });

    test('an empty file fails rather than throws', () {
      expect(DocumentLoader.load(Uint8List(0), 'nothing.docx').failed, isTrue);
      expect(DocumentLoader.load(Uint8List(0), 'nothing.xlsx').failed, isTrue);
    });

    test('a valid zip with the wrong payload fails as a format problem',
        () async {
      // Take a real workbook and lie about it in a way the byte sniff cannot
      // see, by asking for the parse directly.
      final loaded = DocumentLoader.load(
        await documentBytes(kPressRunCosts),
        'press-run-costs.xlsx',
      );
      expect(loaded.failed, isFalse);

      final notAnOffice = Uint8List.fromList(<int>[
        0x50, 0x4B, 0x03, 0x04,
        ...List<int>.generate(200, (i) => (i * 3) % 251),
      ]);
      final bad = DocumentLoader.load(notAnOffice, 'pretend.docx');
      expect(bad.failed, isTrue);
    });

    test('a parser that returns nothing is a failure, not a success', () {
      // The worse failure: the parse works, and the reader is shown a blank
      // sheet with no explanation.
      final empty = Uint8List.fromList('   \n\n   \n'.codeUnits);
      final loaded = DocumentLoader.load(empty, 'blank.md');
      expect(loaded.failed, isTrue,
          reason: 'an empty parse must not be reported as ready');
      expect(loaded.error, isA<FormatException>());

      final emptyCsv = DocumentLoader.load(Uint8List(0), 'blank.csv');
      expect(emptyCsv.failed, isTrue);
    });

    test('a file with real content is not mistaken for an empty one',
        () async {
      for (final name in <String>[
        kHouseStyle,
        kPressRunCosts,
        kSubscribers,
        kBinderyNotes,
      ]) {
        expect((await loadedDocument(name)).failed, isFalse, reason: name);
      }
    });
  });

  group('the bundled library', () {
    test('the seven entries match the files on the shelf', () {
      expect(libraryEntries.length, 7);
      expect(libraryEntries.map((e) => e.format).toList(), <DocFormat>[
        DocFormat.pdf,
        DocFormat.pdf,
        DocFormat.docx,
        DocFormat.xlsx,
        DocFormat.pptx,
        DocFormat.csv,
        DocFormat.md,
      ]);
      expect(libraryEntries.map((e) => e.mark).toList(),
          <String>['PDF', 'PDF', 'DOC', 'XLS', 'PPT', 'CSV', 'MD']);
    });

    test('every declared byte count is the real file size', () async {
      for (final entry in libraryEntries) {
        final bytes = await documentBytes(entry.fileName);
        expect(bytes.length, entry.bytes, reason: entry.fileName);
      }
    });

    test('every declared title is what the file name derives to', () {
      for (final entry in libraryEntries) {
        expect(entry.title, DocumentLoader.titleFor(entry.fileName));
      }
    });

    test('the size label is what the card prints', () {
      expect(libraryEntries.first.sizeLabel, '306 KB');
      expect(libraryEntries[1].sizeLabel, '20 KB');
      expect(
        const LibraryEntry(
          path: 'a/b.md',
          title: 'B',
          format: DocFormat.md,
          bytes: 512,
        ).sizeLabel,
        '512 B',
      );
    });
  });

  group('reading time', () {
    test('minutes round up and never go negative', () {
      expect(readingMinutes(0), 0);
      expect(readingMinutes(-5), 0);
      expect(readingMinutes(1), 1);
      expect(readingMinutes(240), 1);
      expect(readingMinutes(241), 2);
      expect(readingMinutes(14200), 60);
    });

    test('a real document reports a real number of minutes', () async {
      final store = await storeFor(kHouseStyle);
      expect(store.wordCount, 1565);
      expect(store.minutes, 7);
    });
  });

  group('the document store', () {
    test('a good file becomes ready and a bad one becomes failed', () async {
      final ready = await storeFor(kBinderyNotes);
      expect(ready.state, ParseState.ready);
      expect(ready.document, isNotNull);

      final broken = DocumentStore(entryFor(kHouseStyle))
        ..loadFrom(Uint8List.fromList(const <int>[1, 2, 3, 4]));
      expect(broken.state, ParseState.failed);
      expect(broken.document, isNull);
    });

    test('a grid counts rows and a prose document counts blocks', () async {
      final grid = await storeFor(kSubscribers);
      expect(grid.isGrid, isTrue);
      expect(grid.unitCount, 71);

      final prose = await storeFor(kBinderyNotes);
      expect(prose.isGrid, isFalse);
      expect(prose.unitCount, 57);
    });

    test('the position label reads the way its format wants to be read',
        () async {
      final grid = (await storeFor(kSubscribers))..position = 23;
      expect(grid.positionLabel, '24 / 71');

      final prose = (await storeFor(kBinderyNotes))..position = 21;
      expect(prose.positionLabel, '39%');

      final pdf = DocumentStore(entryFor(kPressLease))
        ..pdfPageCount = 6
        ..position = 3;
      expect(pdf.positionLabel, '4 / 6');
    });

    test('moving the reader marks the document as opened and notifies',
        () async {
      final store = await storeFor(kBinderyNotes);
      var notifications = 0;
      store.addListener(() => notifications++);

      expect(store.opened, isFalse);
      store.position = 4;
      expect(store.opened, isTrue);
      expect(notifications, 1);

      store.position = 4;
      expect(notifications, 1, reason: 'no move, no notification');
    });

    test('a dog ear toggles and a signature sticks', () async {
      final store = await storeFor(kBinderyNotes);
      expect(store.dogEared, isEmpty);
      store.toggleDogEar(3);
      expect(store.dogEared, <int>{3});
      store.toggleDogEar(3);
      expect(store.dogEared, isEmpty);

      expect(store.signed, isFalse);
      store.placeSignature(const PlacedSignature(
        pageIndex: 1,
        rect: Rect.fromLTWH(40, 600, 160, 60),
        strokes: <List<Offset>>[
          <Offset>[Offset(0, 1), Offset(1, 0)],
        ],
      ));
      expect(store.signed, isTrue);
      expect(store.signatures.single.pageIndex, 1);
    });

    test('the search is built once and kept', () async {
      final store = await storeFor(kBinderyNotes);
      final first = store.search;
      expect(first, isNotNull);
      expect(identical(store.search, first), isTrue);
    });
  });

  group('the desk', () {
    test('the default shelf shows everything', () {
      final desk = LibraryStore();
      expect(desk.visible.length, 7);
      expect(desk.shelf, Shelf.all);
      expect(desk.countOn(Shelf.reading), 0);
      expect(desk.countOn(Shelf.signed), 0);
      desk.dispose();
    });

    test('the query filters on title and on format, with no debounce',
        () async {
      final desk = LibraryStore();
      desk.query = 'press';
      expect(desk.visible.map((e) => e.title).toList(),
          <String>['Press Lease', 'Press Run Costs', 'Press Day Briefing']);

      desk.query = 'PDF';
      expect(desk.visible.length, 2);

      desk.query = 'vellum';
      expect(desk.visible, isEmpty);

      desk.query = '';
      expect(desk.visible.length, 7);
      desk.dispose();
    });

    test('READING holds what has been opened, SIGNED what has been signed',
        () async {
      final desk = LibraryStore();
      final notes = entryFor(kBinderyNotes);
      desk.storeFor(notes)
        ..loadFrom(await documentBytes(kBinderyNotes))
        ..markOpened();

      expect(desk.countOn(Shelf.reading), 1);
      desk.shelf = Shelf.reading;
      expect(desk.visible.single.title, 'Bindery Notes');

      desk.storeFor(notes).placeSignature(const PlacedSignature(
            pageIndex: 0,
            rect: Rect.fromLTWH(0, 0, 10, 10),
            strokes: <List<Offset>>[],
          ));
      expect(desk.countOn(Shelf.signed), 1);
      desk.dispose();
    });

    test('a removal is retained until it is committed', () {
      final desk = LibraryStore();
      final lease = libraryEntries[1];

      desk.remove(lease);
      expect(desk.entries.length, 6);
      expect(desk.lastRemoved, lease);

      desk.undoRemove();
      expect(desk.entries.length, 7);
      expect(desk.lastRemoved, isNull);

      desk.remove(lease);
      desk.commitRemoval();
      expect(desk.entries.length, 6);
      expect(desk.lastRemoved, isNull);
      desk.dispose();
    });

    test('the colophon counts only what has actually been parsed', () async {
      final desk = LibraryStore();
      expect(desk.documentCount, 7);
      expect(desk.wordCount, 0);
      expect(desk.minutes, 0);

      desk.storeFor(entryFor(kHouseStyle))
          .loadFrom(await documentBytes(kHouseStyle));
      desk.storeFor(entryFor(kBinderyNotes))
          .loadFrom(await documentBytes(kBinderyNotes));

      expect(desk.wordCount, 1565 + 1010);
      expect(desk.minutes, readingMinutes(2575));
      desk.dispose();
    });

    test('the desk notifies when one of its documents changes', () async {
      final desk = LibraryStore();
      var notifications = 0;
      desk.addListener(() => notifications++);

      desk.storeFor(entryFor(kBinderyNotes))
          .loadFrom(await documentBytes(kBinderyNotes));
      expect(notifications, 1);

      desk.storeFor(entryFor(kBinderyNotes)).position = 2;
      expect(notifications, 2);
      desk.dispose();
    });
  });
}
