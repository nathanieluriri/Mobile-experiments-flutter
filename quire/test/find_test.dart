import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/model/search.dart';
import 'package:quire/pdf/display_list.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/pdf/interpreter.dart';
import 'package:quire/pdf/pdf_search.dart';
import 'package:quire/screens/reader/find/find_field.dart';
import 'package:quire/screens/reader/find/find_layer.dart';
import 'package:quire/screens/reader/find/match_sweep.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/theme/typography.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('find reaches every format', () {
    test('Markdown, through the prose index', () async {
      final source = DocFindSource(searchFor(await parsedDocument(kBinderyNotes)));
      final hits = source.find('grain');
      expect(hits.length, 11);
      expect(hits.first.snippet.toLowerCase(), contains('grain'));
      expect(hits.first.path.length, 1, reason: 'a prose hit is one block deep');
      expect(_isSorted(hits.map((h) => h.position)), isTrue);
      expect(hits.last.position, lessThanOrEqualTo(1));
    });

    test('Word, through the same index', () async {
      final source = DocFindSource(searchFor(await parsedDocument(kHouseStyle)));
      expect(source.find('fold').length, 2);
      expect(source.find('paper').length, 3);
      expect(source.find('in').length, 145);
    });

    test('Excel, through the grid scan and not an index', () async {
      final doc = await parsedDocument(kPressRunCosts);
      final search = searchFor(doc);
      expect(search, isA<GridSearch>());
      final hits = DocFindSource(search).find('ream');
      expect(hits.length, 10);
      expect(
        hits.first.path.length,
        4,
        reason: 'a grid hit carries block, row, column and sub block',
      );
      expect(hits.map((h) => h.label).toSet(), isNot(contains('')));
    });

    test('CSV, quoted fields and all', () async {
      final source = DocFindSource(searchFor(await parsedDocument(kSubscribers)));
      expect(source.find('Folio').length, 16);
      expect(source.find('folio').length, 16, reason: 'case never matters');
      expect(source.find('Ardenhollow').length, 1);
    });

    test('PDF, through the merged run index', () async {
      final search = await _pdfSearch(kFieldGuide);
      final source = PdfFindSource(search);
      final hits = source.find('grain');
      expect(hits.length, 30);
      expect(hits.map((h) => h.unit).toSet().length, greaterThan(1));
      expect(_isSorted(hits.map((h) => h.position)), isTrue);
      final rects = search.search('grain').map((h) => h.rect);
      expect(rects.every((r) => r.width > 0 && r.height > 0), isTrue);
    });

    test('a PDF with uncompressed streams searches the same way', () async {
      final source = PdfFindSource(await _pdfSearch(kPressLease));
      expect(source.find('lease').length, 11);
      expect(source.find('LEASE').length, 11);
    });
  });

  group('the three results that break a find', () {
    testWidgets('nothing at all', (tester) async {
      final finder = await _controllerOver(kBinderyNotes);
      finder.type('quorum');
      expect(finder.matches, isEmpty);
      expect(finder.failed, isTrue);
      expect(finder.canStep, isFalse);
      expect(finder.positions, isEmpty);
      expect(finder.livePosition, isNull);
      expect(finder.railOpacity, 0, reason: 'no ticks to fade in');
      finder.dispose();
    });

    testWidgets('nothing at all, in every one of the five formats', (
      tester,
    ) async {
      for (final name in <String>[
        kBinderyNotes,
        kHouseStyle,
        kPressRunCosts,
        kSubscribers,
      ]) {
        final source = DocFindSource(searchFor(await parsedDocument(name)));
        expect(source.find('quorum'), isEmpty, reason: name);
      }
      expect(PdfFindSource(await _pdfSearch(kFieldGuide)).find('quorum'),
          isEmpty);
    });

    testWidgets('exactly one', (tester) async {
      final finder = await _controllerOver(kPressRunCosts);
      finder.type('paper');
      expect(finder.matches.length, 1);
      expect(finder.current, 0);
      expect(finder.canStep, isFalse, reason: 'one match is not a step');
      finder
        ..next()
        ..previous();
      expect(finder.current, 0, reason: 'the chevrons must not move it');
      expect(finder.positions.length, 1);
      expect(finder.livePosition, finder.matches.first.position);
      finder.dispose();
    });

    testWidgets('hundreds', (tester) async {
      final finder = await _controllerOver(kBinderyNotes);
      finder.type('e');
      expect(finder.matches.length, 617);
      expect(finder.positions.length, 617);
      expect(
        finder.unitCounts.fold<int>(0, (a, b) => a + b),
        617,
        reason: 'every match belongs to exactly one unit',
      );
      expect(finder.sweep.schedule.count, 617);
      expect(
        finder.sweep.schedule.staggerMs,
        lessThan(kSweepStagger.inMilliseconds),
        reason: 'the stagger compresses rather than the sweep running long',
      );
      expect(finder.sweep.schedule.spanMs, closeTo(kSweepCap.inMilliseconds, 0.5));
      finder.dispose();
    });
  });

  group('the field', () {
    test('grows leftward out of the search pill, right edge fixed', () {
      expect(findFieldLeft(0), kScreenWidth - kScreenPadding - kHeaderButtonSize);
      expect(findFieldLeft(1), kScreenPadding);
      expect(findFieldLeft(0.5), greaterThan(kScreenPadding));
      expect(findFieldLeft(2), kScreenPadding, reason: 'clamped, never past');
      expect(kFindFieldRight, 382);
      expect(
        kFindFieldTop,
        kHeadBandTop + (kHeadBandHeight - kFindFieldHeight) / 2,
        reason: 'the field and the pill share a top edge',
      );
    });
  });

  group('the controller', () {
    testWidgets('every keystroke queries, with no debounce', (tester) async {
      final finder = await _controllerOver(kBinderyNotes);
      finder.type('g');
      final one = finder.matches.length;
      finder.type('gr');
      final two = finder.matches.length;
      finder.type('gra');
      expect(one, greaterThan(two));
      expect(two, greaterThan(finder.matches.length));
      finder.type('');
      expect(finder.matches, isEmpty);
      expect(finder.hasQuery, isFalse);
      finder.dispose();
    });

    testWidgets('the chevrons wrap rather than dying at the foot', (
      tester,
    ) async {
      final finder = await _controllerOver(kBinderyNotes);
      finder.type('grain');
      expect(finder.current, 0);
      finder.next();
      expect(finder.current, 1);
      finder.previous();
      expect(finder.current, 0);
      finder.previous();
      expect(finder.current, 10, reason: 'back from the first is the last');
      finder.next();
      expect(finder.current, 0);
      finder.dispose();
    });

    testWidgets('a block is handed its own matches, in document order', (
      tester,
    ) async {
      final doc = await parsedDocument(kBinderyNotes);
      final finder = FindController(
        vsync: const TestVSync(),
        source: DocFindSource(searchFor(doc)),
      );
      finder.type('grain');
      final ordinals = <int>[];
      for (var i = 0; i < doc.sections.first.blocks.length; i++) {
        for (final range in finder.rangesIn(0, <int>[i])) {
          ordinals.add(range.ordinal);
          expect(range.end - range.start, 5);
        }
      }
      expect(ordinals, List<int>.generate(11, (i) => i));
      expect(finder.rangesIn(0, const <int>[9999]), isEmpty);
      finder.dispose();
    });

    testWidgets('a failed search never moves the document', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      store.position = 12;
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('quorum');
      await tester.pump();
      await pumpMs(tester, 200);
      expect(store.position, 12);
      expect(finder.tint, 1, reason: 'the field tints and nothing else moves');
      await _release(tester, finder);
    });

    testWidgets('the field is what types into it', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      expect(finder.isOpen, isFalse);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      expect(finder.open, 1);
      expect(finder.text.text, isEmpty);
      expect(finder.tint, 0);
      await tester.enterText(find.byType(EditableText), 'grain');
      await pumpMs(tester, 16);
      expect(finder.matches.length, 11);
      expect(finder.query, 'grain');
      await _release(tester, finder);
    });

    testWidgets('closing fades the washes instead of snapping them off', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('grain');
      await tester.pump();
      await pumpMs(tester, 400);
      expect(finder.frame.opacity, 1);
      finder.closeField();
      await tester.pump();
      await pumpMs(tester, 100);
      expect(finder.frame.opacity, greaterThan(0));
      expect(finder.frame.opacity, lessThan(1));
      await pumpMs(tester, 120);
      expect(finder.frame.opacity, 0);
      await _release(tester, finder);
    });
  });

  group('its goldens', () {
    testWidgets('find__typing', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('g');
      await tester.pump();
      await pumpMs(tester, 60);
      await capture(tester, 'find__typing');
      await _release(tester, finder);
    });

    testWidgets('find__matches', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('grain');
      expect(finder.matches.length, 11);
      await tester.pump();
      await pumpMs(tester, 400);
      await capture(tester, 'find__matches');
      await _release(tester, finder);
    });

    testWidgets('find__many', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('the');
      expect(finder.matches.length, 108);
      await tester.pump();
      await pumpMs(tester, 560);
      await capture(tester, 'find__many');
      await _release(tester, finder);
    });

    testWidgets('find__none', (tester) async {
      final store = await storeFor(kBinderyNotes);
      final doc = await parsedDocument(kBinderyNotes);
      final finder = _controllerFor(doc);
      addTearDown(finder.dispose);
      await _pumpFinder(tester, store: store, doc: doc, find: finder);
      finder.openField();
      await tester.pump();
      await pumpMs(tester, 220);
      finder.type('quorum');
      await tester.pump();
      await pumpMs(tester, 200);
      await capture(tester, 'find__none');
      await _release(tester, finder);
    });
  });
}

bool _isSorted(Iterable<double> values) {
  double last = -1;
  for (final value in values) {
    if (value < last) return false;
    last = value;
  }
  return true;
}

Future<PdfSearch> _pdfSearch(String fileName) async {
  final file = PdfFile.open(await documentBytes(fileName));
  final lists = <PageDisplayList>[
    for (var i = 0; i < file.pageCount; i++)
      ContentInterpreter(file).run(file.pages[i]),
  ];
  return PdfSearch.fromDisplayLists(lists);
}

FindController _controllerFor(QuireDocument doc) =>
    FindController(vsync: const TestVSync(), source: DocFindSource(searchFor(doc)));

/// A controller over a bundled document, for the tests that need no tree.
Future<FindController> _controllerOver(String fileName) async =>
    _controllerFor(await parsedDocument(fileName));

/// Lets go of the field, so the caret's blink timer is not still pending when
/// the tree comes down.
Future<void> _release(WidgetTester tester, FindController finder) async {
  finder.focusNode.unfocus();
  await tester.pump(const Duration(seconds: 1));
}

/// The reader with the find layer over it, on a real bundled document.
Future<void> _pumpFinder(
  WidgetTester tester, {
  required DocumentStore store,
  required QuireDocument doc,
  required FindController find,
}) async {
  await pumpScreen(
    tester,
    ListenableBuilder(
      listenable: find,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ReaderScreen(
          store: store,
          bodyBuilder: (context) => _ProseStub(doc: doc, finder: find),
          matches: find.positions,
          liveMatch: find.livePosition,
          matchOpacity: find.railOpacity,
          matchCounts: find.unitCounts,
          overlay: FindLayer(controller: find),
          onFind: find.openField,
        ),
      ),
    ),
  );
}

/// A prose body: the document's blocks at reading size, with the highlighter
/// painted under every match the find knows about.
///
/// The real bodies belong to other packages. What the sweep depends on is only
/// this much of one: a block, its text, and the ordinals the find hands back.
class _ProseStub extends ReaderBody {
  const _ProseStub({required this.doc, required this.finder});

  final QuireDocument doc;
  final FindController finder;

  @override
  Widget buildFront(BuildContext context) {
    final blocks = doc.sections.first.blocks;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(kSheetPadding),
      itemCount: blocks.length,
      itemBuilder: (context, index) => _block(blocks[index], index),
    );
  }

  Widget _block(DocBlock block, int index) {
    final ranges = finder.rangesIn(0, <int>[index]);
    final frame = finder.frame;
    switch (block) {
      case HeadingBlock():
        return Padding(
          padding: const EdgeInsets.only(top: kSpace16, bottom: kSpace4),
          child: SweptText(
            block.text,
            style: _heading(block.level),
            ranges: ranges,
            frame: frame,
          ),
        );
      case ParagraphBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: kSpace8),
          child: SweptText(
            block.text,
            style: AppText.pageBody.copyWith(color: AppColors.ink),
            ranges: ranges,
            frame: frame,
          ),
        );
      case ListItemBlock():
        return Padding(
          padding: EdgeInsets.only(
            left: kSpace16 * (block.level + 1),
            bottom: kSpace4,
          ),
          child: SweptText(
            block.text,
            style: AppText.pageBody.copyWith(color: AppColors.ink),
            ranges: ranges,
            frame: frame,
          ),
        );
      case CodeBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: kSpace8),
          child: ColoredBox(
            color: AppColors.surfaceHigh,
            child: Padding(
              padding: const EdgeInsets.all(kSpace8),
              child: SweptText(
                block.text,
                style: AppText.code.copyWith(color: AppColors.inkSoft),
                ranges: ranges,
                frame: frame,
              ),
            ),
          ),
        );
      case DividerBlock():
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: kSpace12),
          child: SizedBox(height: 1, child: ColoredBox(color: AppColors.hairline)),
        );
      case ImageBlock():
      case TableBlock():
        return const SizedBox.shrink();
    }
  }

  static TextStyle _heading(int level) {
    switch (level) {
      case 1:
        return AppText.pageHeading1.copyWith(color: AppColors.ink);
      case 2:
        return AppText.pageHeading2.copyWith(color: AppColors.ink);
      default:
        return AppText.pageHeading3.copyWith(color: AppColors.ink);
    }
  }

  @override
  Widget buildBack(BuildContext context) => const SizedBox.expand();

  @override
  int get unitCount => doc.sections.first.blocks.length;

  @override
  String get positionLabel => '1 / $unitCount';

  @override
  List<double> get foreEdgeMarks {
    final blocks = doc.sections.first.blocks;
    final last = (blocks.length - 1).clamp(1, blocks.length);
    return <double>[
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i] is HeadingBlock) i / last,
    ];
  }
}
