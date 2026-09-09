import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/model/search.dart';
import 'package:quire/screens/reader/find/find_layer.dart';
import 'package:quire/screens/reader/find/match_sweep.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/reader/sheet_surface.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/theme/typography.dart';
import 'package:quire/widgets/marked_text.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the schedule', () {
    test('nothing to sweep costs nothing', () {
      const empty = SweepSchedule(0);
      expect(empty.duration, Duration.zero);
      expect(empty.staggerMs, 0);
      expect(empty.spanMs, 0);
      expect(empty.fillAt(0, 1000), 0);
      expect(empty.liveAt(0, 1000), 0);
    });

    test('one match is one stroke and no stagger', () {
      const one = SweepSchedule(1);
      expect(one.staggerMs, 0);
      expect(one.spanMs, 0);
      expect(one.duration, const Duration(milliseconds: 140));
      expect(one.startAt(0), 0);
    });

    test('strokes start 24 ms apart until the cap says otherwise', () {
      const six = SweepSchedule(6);
      expect(six.staggerMs, 24);
      expect(six.startAt(3), 72);
      expect(six.spanMs, 120);
      expect(six.duration, const Duration(milliseconds: 260));
    });

    test('seventeen is the last count that fits at the full stagger', () {
      expect(const SweepSchedule(17).staggerMs, kSweepStagger.inMilliseconds);
      expect(const SweepSchedule(17).spanMs, 384);
      expect(
        const SweepSchedule(18).staggerMs,
        lessThan(kSweepStagger.inMilliseconds),
      );
    });

    test('past that the stagger compresses and the span holds at the cap', () {
      for (final count in <int>[18, 40, 108, 240, 617]) {
        final schedule = SweepSchedule(count);
        expect(
          schedule.spanMs,
          closeTo(kSweepCap.inMilliseconds, 0.001),
          reason: '$count matches',
        );
        expect(schedule.staggerMs, lessThan(kSweepStagger.inMilliseconds));
      }
    });

    test('a stroke grows from nothing to the whole word on easeOutQuad', () {
      const six = SweepSchedule(6);
      expect(six.fillAt(0, 0), 0);
      expect(six.fillAt(0, 70), closeTo(0.75, 0.0001));
      expect(six.fillAt(0, 140), 1);
      expect(six.fillAt(0, 4000), 1);
      expect(six.fillAt(2, 47), 0, reason: 'its turn has not come');
      expect(six.fillAt(2, 48 + 140), 1);
      expect(six.fillAt(-1, 200), 0);
      expect(six.fillAt(99, 200), 0);
    });

    test('the second pass waits for the first to finish', () {
      const six = SweepSchedule(6);
      expect(six.liveAt(0, 140), 0);
      expect(six.liveAt(0, 200), closeTo(0.75, 0.0001));
      expect(six.liveAt(0, 260), 1);
      expect(six.liveAt(4, 140), 0, reason: 'the fifth stroke is not drawn yet');
    });
  });

  group('a frame', () {
    test('an ordinary match is markerWash and the current one is markerLive',
        () {
      const frame = SweepFrame(
        schedule: SweepSchedule(3),
        elapsedMs: 1000,
        current: 1,
        liveFraction: 1,
      );
      expect(frame.colorOf(0), AppColors.foundWash);
      expect(frame.colorOf(2), AppColors.foundWash);
      expect(frame.colorOf(1), AppColors.foundLive);
      expect(frame.fillOf(0), 1);
      expect(frame.fillOf(2), 1);
    });

    test('half way through the second pass is half way between the two', () {
      const frame = SweepFrame(
        schedule: SweepSchedule(3),
        elapsedMs: 1000,
        current: 0,
        liveFraction: 0.5,
      );
      final live = frame.colorOf(0);
      expect(live.a, greaterThan(AppColors.foundWash.a));
      expect(live.a, lessThan(AppColors.foundLive.a));
    });

    test('the fade takes every wash down together', () {
      const frame = SweepFrame(
        schedule: SweepSchedule(3),
        elapsedMs: 1000,
        current: 0,
        liveFraction: 1,
        opacity: 0.5,
      );
      expect(frame.colorOf(1).a, closeTo(AppColors.foundWash.a * 0.5, 0.001));
      expect(frame.colorOf(0).a, closeTo(AppColors.foundLive.a * 0.5, 0.001));
    });

    test('the rail fades in with the sweep, not before it', () {
      expect(SweepFrame.idle.railOpacity, 0);
      expect(const SweepFrame(schedule: SweepSchedule(6)).railOpacity, 0);
      expect(
        const SweepFrame(schedule: SweepSchedule(6), elapsedMs: 200)
            .railOpacity,
        1,
      );
      expect(
        const SweepFrame(schedule: SweepSchedule(6), elapsedMs: 100)
            .railOpacity,
        closeTo(0.75, 0.0001),
      );
    });
  });

  group('the one controller', () {
    testWidgets('washes, relights and fades on a single ticker', (
      tester,
    ) async {
      final sweep = MatchSweep(vsync: const TestVSync());
      addTearDown(sweep.dispose);
      await tester.pumpWidget(const SizedBox.shrink());

      sweep.sweep(6);
      await tester.pump();
      expect(sweep.frame.elapsedMs, 0);
      expect(sweep.frame.fillOf(0), 0);
      await pumpMs(tester, 140);
      expect(sweep.frame.fillOf(0), 1);
      expect(sweep.frame.fillOf(5), lessThan(1));
      await pumpMs(tester, 260);
      expect(sweep.frame.fillOf(5), 1);
      expect(sweep.frame.liveFraction, 1);

      sweep.relight(3);
      await tester.pump();
      expect(sweep.current, 3);
      expect(sweep.frame.fillOf(5), 1, reason: 'no second light show');
      expect(sweep.frame.liveFraction, 0);
      await pumpMs(tester, 120);
      expect(sweep.frame.liveFraction, 1);

      sweep.fade();
      await tester.pump();
      expect(sweep.frame.opacity, 1);
      await pumpMs(tester, 200);
      expect(sweep.frame.opacity, 0);
      await pumpMs(tester, 50);
    });

    testWidgets('a query with nothing to show clears the last one', (
      tester,
    ) async {
      final sweep = MatchSweep(vsync: const TestVSync());
      addTearDown(sweep.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      sweep.sweep(4);
      await tester.pump();
      await pumpMs(tester, 400);
      expect(sweep.frame.fillOf(0), 1);
      await tester.pump();
      sweep.sweep(0);
      await tester.pump();
      expect(sweep.schedule.count, 0);
      expect(sweep.current, -1);
      expect(sweep.frame.fillOf(0), 0);
    });
  });

  group('what the page paints', () {
    testWidgets('a mark is a MarkedText run, not a new species', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: SweptText(
                'Fold with the grain and the paper yields.',
                style: AppText.pageBody,
                ranges: const <SweptRange>[
                  SweptRange(start: 14, end: 19, ordinal: 0),
                ],
                frame: const SweepFrame(
                  schedule: SweepSchedule(1),
                  elapsedMs: 70,
                  current: 0,
                ),
              ),
            ),
          ),
        ),
      );
      final marked = tester.widget<MarkedText>(find.byType(MarkedText));
      expect(marked.marks.length, 1);
      expect(marked.marks.first.start, 14);
      expect(marked.marks.first.end, 19);
      expect(marked.marks.first.fill, closeTo(0.75, 0.0001));
      expect(marked.marks.first.color, AppColors.foundWash);
    });
  });

  group('its keyframes', () {
    testWidgets('sweep__t0000', (tester) async {
      final finder = await _pumpSweep(tester);
      await capture(tester, 'sweep__t0000');
      await _release(tester, finder);
    });

    testWidgets('sweep__t0140', (tester) async {
      final finder = await _pumpSweep(tester);
      await pumpMs(tester, 140);
      await capture(tester, 'sweep__t0140');
      await _release(tester, finder);
    });

    testWidgets('sweep__t0400', (tester) async {
      final finder = await _pumpSweep(tester);
      await pumpMs(tester, 400);
      await capture(tester, 'sweep__t0400');
      await _release(tester, finder);
    });
  });
}

/// Opens the find over the Markdown notes, types the query, and leaves the
/// clock standing at the frame the first stroke begins on.
Future<FindController> _pumpSweep(WidgetTester tester) async {
  final store = await storeFor(kBinderyNotes);
  final doc = await parsedDocument(kBinderyNotes);
  final finder = FindController(
    vsync: const TestVSync(),
    source: DocFindSource(searchFor(doc)),
  );
  addTearDown(finder.dispose);
  await pumpScreen(
    tester,
    ListenableBuilder(
      listenable: finder,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ReaderScreen(
          store: store,
          bodyBuilder: (context) => _ProseStub(doc: doc, finder: finder),
          matches: finder.positions,
          liveMatch: finder.livePosition,
          matchOpacity: finder.railOpacity,
          matchCounts: finder.unitCounts,
          overlay: FindLayer(controller: finder),
          onFind: finder.openField,
        ),
      ),
    ),
  );
  finder.openField();
  await tester.pump();
  await pumpMs(tester, 220);
  finder.type('grain');
  await tester.pump();
  return finder;
}

/// Lets go of the field, so the caret's blink timer is not still pending when
/// the tree comes down.
Future<void> _release(WidgetTester tester, FindController finder) async {
  finder.focusNode.unfocus();
  await tester.pump(const Duration(seconds: 1));
}

/// A prose body: the document's blocks at reading size, with the highlighter
/// painted under every match the find knows about.
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
