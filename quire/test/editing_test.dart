import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/ooxml_patch.dart';
import 'package:quire/edit/xlsx_patch.dart';
import 'package:quire/format/xlsx_parser.dart' show XlsxParser;
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/screens/edit/markup_screen.dart';
import 'package:quire/screens/edit/paragraph_editor.dart';
import 'package:quire/screens/edit/revisions_sheet.dart';
import 'package:quire/screens/edit/text_editor.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart' show PdfPageView;
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/services/revisions.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('What can be done with this document'));
  await settle(tester);
}

/// Lets the disk catch up: file reads and writes do not run on the test's
/// clock.
Future<void> _disk(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await settle(tester);
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('editing');
  });
  tearDown(() => root.delete(recursive: true));

  Future<(LibraryStore, DocumentStore)> open(
    WidgetTester tester,
    String name, {
    bool keeps = true,
  }) async {
    final library = LibraryStore(
      revisions: keeps ? RevisionStore(() async => root) : null,
    );
    final entry = entryFor(name);
    final bytes = (await tester.runAsync(() => documentBytes(name)))!;
    final store = library.storeFor(entry)..loadFrom(bytes);
    await pumpScreen(
      tester,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ReaderHost(store: store, library: library),
      ),
    );
    await settle(tester);
    return (library, store);
  }

  group('what can be edited is offered', () {
    testWidgets('nothing, on a desk that cannot keep a change', (tester) async {
      await open(tester, kBinderyNotes, keeps: false);
      await _openMenu(tester);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Revisions'), findsNothing);
    });

    testWidgets('Mark up on a PDF, a cell on a workbook, Edit on the rest',
        (tester) async {
      await open(tester, kFieldGuide);
      await _openMenu(tester);
      expect(find.text('Mark up'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Revisions'), findsOneWidget);
    });

    testWidgets('a workbook edits a cell', (tester) async {
      await open(tester, kPressRunCosts);
      await _openMenu(tester);
      expect(find.text('Edit this cell'), findsOneWidget);
      expect(find.text('Edit'), findsNothing);
    });
  });

  testWidgets('Markdown is edited as text, saved as a revision, and the '
      'original can be read again', (tester) async {
    final (library, store) = await open(tester, kBinderyNotes);
    final before = store.bytes;
    await _openMenu(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byType(TextEditor), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '# Changed\n\nNew words here.');
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('See the page it makes'));
    await tester.pump(kPreviewRest);
    await settle(tester);
    expect(find.textContaining('New words here', findRichText: true), findsWidgets);

    await tester.tap(find.text('SAVE'));
    await _disk(tester);
    expect(find.byType(TextEditor), findsNothing);
    expect(find.text(kEditSaved), findsOneWidget);
    expect(String.fromCharCodes(store.bytes), contains('New words here.'));
    final history = (await tester.runAsync(() => library.historyOf(store.entry)))!;
    expect(history.current, 1);

    await _openMenu(tester);
    await tester.tap(find.text('Revisions'));
    await _disk(tester);
    expect(find.byType(RevisionsSheet), findsOneWidget);
    expect(find.text('Revision 1, being read'), findsOneWidget);
    await tester.tap(find.text('The original'));
    await settle(tester);
    await tester.tap(find.text('Read this one'));
    await _disk(tester);
    expect(store.bytes, before);
    final after = (await tester.runAsync(() => library.historyOf(store.entry)))!;
    expect(after.revisions.map((r) => r.number), [1, 2]);
  });

  testWidgets('a Word paragraph is changed and the rest of the file kept',
      (tester) async {
    final (_, store) = await open(tester, kHouseStyle);
    final was = DocxPatch(store.bytes).paragraphs;
    final at = was.indexWhere((p) => p.length > 20);
    await _openMenu(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byType(ParagraphEditor), findsOneWidget);
    final field = find.descendant(
      of: find.byKey(ValueKey<String>('paragraph $at')),
      matching: find.byType(EditableText),
    );
    await tester.scrollUntilVisible(
      find.byKey(ValueKey<String>('paragraph $at')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ParagraphEditor),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(field, 'Rewritten in quire.');
    await settle(tester);
    expect(find.text('One paragraph changed.'), findsOneWidget);
    await tester.tap(find.text('SAVE'));
    await _disk(tester);
    final now = DocxPatch(store.bytes).paragraphs;
    expect(now[at], 'Rewritten in quire.');
    for (var i = 0; i < was.length; i++) {
      if (i != at) expect(now[i], was[i]);
    }
  });

  testWidgets('a cell is changed from the sheet', (tester) async {
    final (_, store) = await open(tester, kPressRunCosts);
    final sheet = XlsxPatch(store.bytes).sheetNames[SheetController.of(store).sheet];
    SheetController.of(store).selected = const SheetCell(1, 1);
    await settle(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Edit this cell'));
    await settle(tester);
    expect(find.text('$sheet!B2'), findsWidgets);
    await tester.enterText(find.byType(EditableText), '4321');
    await tester.tap(find.text('Save the cell'));
    await _disk(tester);
    final cell = XlsxParser(store.bytes)
        .parse()
        .sheets
        .firstWhere((s) => s.name == sheet)
        .cell('B2');
    expect(cell?.raw, 4321);
  });

  testWidgets('a highlight dragged over a PDF page is written into the file',
      (tester) async {
    final (library, store) = await open(tester, kFieldGuide);
    final pdf = store.pdf!;
    final had = (pdf.resolve(pdf.pages[0]['Annots']) as List?)?.length ?? 0;
    await _openMenu(tester);
    await tester.tap(find.text('Mark up'));
    await settle(tester);
    expect(find.byType(MarkupScreen), findsOneWidget);

    final page = tester.getRect(
      find.descendant(
        of: find.byType(MarkupScreen),
        matching: find.byType(PdfPageView),
      ),
    );
    await tester.dragFrom(
      page.topLeft + Offset(page.width * 0.1, page.height * 0.2),
      Offset(page.width * 0.6, page.height * 0.05),
    );
    await settle(tester);
    await tester.tap(find.text('SAVE'));
    await _disk(tester);
    expect(find.byType(MarkupScreen), findsNothing);

    final again = store.pdf!;
    expect(identical(again, pdf), isFalse);
    final annots = (again.resolve(again.pages[0]['Annots'])! as List)
        .map(again.dict)
        .toList();
    expect(annots, hasLength(had + 1));
    expect((annots.last!['Subtype']! as PdfName).value, 'Highlight');
    expect(store.revised, isTrue);
    expect(tester.takeException(), isNull);
    expect(library, isNotNull);
  });

  testWidgets('deleting a revision asks once, and says it cannot be undone',
      (tester) async {
    final (library, store) = await open(tester, kSubscribers);
    await tester.runAsync(() async {
      await library.saveEdit(store.entry, store.bytes, note: 'one');
      await library.saveEdit(store.entry, store.bytes, note: 'two');
    });
    await settle(tester);
    await _openMenu(tester);
    await tester.tap(find.text('Revisions'));
    await _disk(tester);
    await tester.tap(find.text('Revision 1'));
    await settle(tester);
    await tester.tap(find.text('Delete this revision'));
    await settle(tester);
    expect(find.textContaining('cannot be brought back'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await _disk(tester);
    var history = (await tester.runAsync(() => library.historyOf(store.entry)))!;
    expect(history.revisions, hasLength(2));

    await _openMenu(tester);
    await tester.tap(find.text('Revisions'));
    await _disk(tester);
    await tester.tap(find.text('Forget the others'));
    await settle(tester);
    await tester.tap(find.text('Forget them'));
    await _disk(tester);
    history = (await tester.runAsync(() => library.historyOf(store.entry)))!;
    expect(history.revisions.map((r) => r.number), [2]);
  });

  test('deleting a document for good deletes its revisions', () async {
    final revisions = RevisionStore(() async => root);
    final library = LibraryStore(revisions: revisions);
    final entry = entryFor(kSubscribers);
    final bytes = await documentBytes(kSubscribers);
    library.storeFor(entry).loadFrom(bytes);
    await library.saveEdit(entry, bytes, note: 'kept');
    expect((await revisions.history(entry.path)).revisions, hasLength(1));
    library.deleteForever(entry);
    expect((await revisions.history(entry.path)).revisions, isEmpty);
    expect(root.listSync(), isEmpty);
  });

  group('snapping a drag to the lines of type', () {
    LaidOutRun line(double y) => LaidOutRun('a line of words', 50, y, 10, 200, 0, 0, 0);

    test('one line, from where the drag began to where it ended', () {
      final rects = snapToLines([line(100)], const Rect.fromLTRB(80, 95, 150, 99));
      expect(rects, [const Rect.fromLTRB(80, 91, 150, 102.5)]);
    });

    test('three lines: the middle one whole, the ends cut at the drag', () {
      final rects = snapToLines(
        [line(100), line(120), line(140)],
        const Rect.fromLTRB(120, 95, 90, 138).normalize(),
      );
      expect(rects, hasLength(3));
      expect(rects[0].left, 90);
      expect(rects[0].right, 250);
      expect(rects[1].left, 50);
      expect(rects[1].right, 250);
      expect(rects[2].left, 50);
      expect(rects[2].right, 120);
    });

    test('no type under it, which is a scan, is the drag itself', () {
      const drag = Rect.fromLTRB(10, 10, 60, 30);
      expect(snapToLines(const [], drag), [drag]);
    });

    test('a turned line is left alone', () {
      final turned = LaidOutRun('sideways', 50, 100, 10, 200, 0, 0, 0, angle: 1.57);
      expect(snapToLines([turned], const Rect.fromLTRB(60, 95, 70, 99)), [
        const Rect.fromLTRB(60, 95, 70, 99),
      ]);
    });
  });
}

extension on Rect {
  Rect normalize() => Rect.fromPoints(topLeft, bottomRight);
}
