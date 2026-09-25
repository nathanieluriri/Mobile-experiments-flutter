import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show ChangeSource;
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/edit/ooxml_patch.dart';
import 'package:quire/edit/xlsx_patch.dart';
import 'package:quire/format/xlsx_parser.dart' show XlsxParser;
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/objects.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/edit/doc_editor.dart';
import 'package:quire/screens/edit/grid_editor.dart';
import 'package:quire/screens/edit/markup_screen.dart';
import 'package:quire/screens/edit/revisions_sheet.dart';
import 'package:quire/screens/edit/slides/slide_editor.dart';
import 'package:quire/screens/edit/text_editor.dart';
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

  testWidgets('a Word document is edited in place and the rest of the file kept',
      (tester) async {
    final (_, store) = await open(tester, kHouseStyle);
    final was = DocxPatch(store.bytes).paragraphs;
    final at = was.indexWhere((p) => p.length > 20);
    await _openMenu(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.byType(DocEditor), findsOneWidget);
    final editor = tester.state<DocEditorState>(find.byType(DocEditor));
    final offset = editor.controller.document.toPlainText().indexOf(was[at]);
    editor.controller.replaceText(offset, was[at].length, 'Rewritten in quire.', null);
    await settle(tester);
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
    await tester.tap(find.bySemanticsLabel('Highlight'));
    await settle(tester);

    final page = tester.getRect(find.byKey(const ValueKey<String>('markup-page')));
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
    // Each of the fifteen characters is 200 / 15 points wide.
    double at(int index) => 50 + index * 200 / 15;

    test('one line, from the start of the word the drag began in to the end of the one it ended in', () {
      final rects = snapToLines([line(100)], const Offset(80, 97), const Offset(150, 97));
      expect(rects, [Rect.fromLTRB(at(2), 91, at(9), 102.5)]);
    });

    test('three lines: the middle one whole, the ends cut at the words', () {
      final rects = snapToLines(
        [line(100), line(120), line(140)],
        const Offset(120, 95),
        const Offset(90, 138),
      );
      expect(rects, hasLength(3));
      expect(rects[0].left, at(2));
      expect(rects[0].right, 250);
      expect(rects[1].left, 50);
      expect(rects[1].right, 250);
      expect(rects[2].left, 50);
      expect(rects[2].right, at(6));
    });

    test('a drag that drifts under half a line stays on its line', () {
      final rects = snapToLines([line(100), line(120)], const Offset(60, 97), const Offset(200, 101));
      expect(rects, [Rect.fromLTRB(50, 91, 250, 102.5)]);
    });

    test('a tap marks the word under it', () {
      final rects = snapToLines([line(100)], const Offset(100, 97), const Offset(100, 97));
      expect(rects, [Rect.fromLTRB(at(2), 91, at(6), 102.5)]);
    });

    test('no type under it, which is a scan, is the drag itself', () {
      expect(snapToLines(const [], const Offset(10, 10), const Offset(60, 30)), [
        const Rect.fromLTRB(10, 10, 60, 30),
      ]);
    });

    test('a turned line is left alone', () {
      final turned = LaidOutRun('sideways', 50, 100, 10, 200, 0, 0, 0, angle: 1.57);
      expect(snapToLines([turned], const Offset(60, 95), const Offset(70, 99)), [
        const Rect.fromLTRB(60, 95, 70, 99),
      ]);
    });
  });
  group('after the integration critic', () {
    String words(DocBlock block) => switch (block) {
      ParagraphBlock() => block.text,
      HeadingBlock() => block.text,
      ListItemBlock() => block.text,
      _ => '',
    }.trim();

    testWidgets('a deck is edited on the slide being read, and read again on the slide edited', (tester) async {
      final (_, store) = await open(tester, kPressDayBriefing);
      store.position = 3;
      await settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      final editor = tester.state<SlideEditorState>(find.byType(SlideEditor));
      expect(editor.current, 3);
      expect(editor.onSlide, isTrue);
      final deck = editor.deck!;
      final thumb = find.byKey(ValueKey<String>('thumb-${deck.slides[4]}'));
      await tester.ensureVisible(thumb);
      await settle(tester);
      await tester.tap(thumb);
      await settle(tester);
      expect(editor.current, 4);
      final title = deck.objects(deck.slides[4]).first;
      final canvas = tester.getTopLeft(find.byKey(const ValueKey<String>('slide-canvas')));
      final middle = Offset(title.box.left + title.box.width / 2, title.box.top + title.box.height / 2);
      await tester.timedDragFrom(canvas + editor.onCanvas(middle), const Offset(0, 40), const Duration(milliseconds: 300));
      await settle(tester);
      expect(deck.changed, isTrue);
      await tester.tap(find.text('SAVE'));
      await _disk(tester);
      expect(find.byType(SlideEditor), findsNothing);
      expect(store.position, 4);
    });

    testWidgets('a Word document is edited where it is being read, and read again where it was edited', (tester) async {
      final (_, store) = await open(tester, kHouseStyle);
      final blocks = <DocBlock>[for (final section in store.document!.sections) ...section.blocks];
      var at = (blocks.length * 0.6).round();
      while (words(blocks[at]).length < 12) {
        at++;
      }
      store.position = at;
      await settle(tester);
      // A little way back up brings the band back, as it does for a reader.
      await tester.dragFrom(const Offset(200, 500), const Offset(0, 40));
      await settle(tester);
      at = store.position;
      while (words(blocks[at]).length < 12) {
        at++;
      }
      await _openMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      final editor = tester.state<DocEditorState>(find.byType(DocEditor));
      expect(editor.scroll.offset, greaterThan(0));
      expect(editor.place.words, startsWith(words(blocks[at]).substring(0, 12)));
      editor.scroll.jumpTo(editor.scroll.position.maxScrollExtent);
      await settle(tester);
      final text = editor.controller.document.toPlainText();
      final last = text.lastIndexOf(RegExp(r'[a-z]'));
      // Typed where a tap near the end puts the caret.
      editor.controller.updateSelection(TextSelection.collapsed(offset: last + 1), ChangeSource.local);
      editor.controller.replaceText(last + 1, 0, ' more', TextSelection.collapsed(offset: last + 6));
      await settle(tester);
      await tester.tap(find.text('SAVE'));
      await _disk(tester);
      expect(find.byType(DocEditor), findsNothing);
      expect(store.position, greaterThan(store.unitCount * 0.8));
    });

    testWidgets('a CSV is edited from the cell picked in the reader, and read again on the row edited', (tester) async {
      final (_, store) = await open(tester, kSubscribers);
      final sheets = SheetController.of(store);
      sheets.selected = const SheetCell(4, 1);
      await settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      final grid = tester.state<GridEditorState>(find.byType(GridEditor));
      expect(grid.pick, const CellPick(4, 1));
      grid.select(const CellPick(60, 0), edit: true);
      await settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'CHANGED');
      await settle(tester);
      await tester.tap(find.text('SAVE'));
      await _disk(tester);
      expect(find.byType(GridEditor), findsNothing);
      // The row edited is in sight, and its cell ringed.
      expect(store.position, inInclusiveRange(40, 60));
      expect(sheets.selected, const SheetCell(60, 0));
    });

    testWidgets('marks saved on a later page leave the reader on that page', (tester) async {
      final (_, store) = await open(tester, kFieldGuide);
      await _openMenu(tester);
      await tester.tap(find.text('Mark up'));
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.bySemanticsLabel('The page after'));
        await _disk(tester);
      }
      expect(tester.state<MarkupScreenState>(find.byType(MarkupScreen)).page, 2);
      await tester.tap(find.bySemanticsLabel('Highlight'));
      await settle(tester);
      final page = tester.getRect(find.byKey(const ValueKey<String>('markup-page')));
      await tester.dragFrom(
        page.topLeft + Offset(page.width * 0.1, page.height * 0.2),
        Offset(page.width * 0.6, page.height * 0.05),
      );
      await settle(tester);
      await tester.tap(find.text('SAVE'));
      await _disk(tester);
      expect(find.byType(MarkupScreen), findsNothing);
      expect(store.position, 2);
    });
      testWidgets('the saved notice is one line, clear of the search button', (tester) async {
      await open(tester, kBinderyNotes);
      await _openMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), '# Changed\n\nNew words here.');
      await settle(tester);
      await tester.tap(find.text('SAVE'));
      await _disk(tester);
      final notice = tester.getRect(find.text(kEditSaved));
      final search = tester.getRect(find.bySemanticsLabel('Find in document'));
      expect(notice.overlaps(search), isFalse);
      expect(notice.height, lessThan(20));
    });
  });
}
