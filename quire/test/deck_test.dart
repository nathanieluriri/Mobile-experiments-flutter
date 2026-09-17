import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/deck_body.dart';
import 'package:quire/screens/reader/bodies/slide_sheet.dart';
import 'package:quire/screens/reader/folio_chip.dart';
import 'package:quire/screens/reader/present_screen.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _reader(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

/// The bench, scrolled to the slide at [index].
Future<void> _benchTo(WidgetTester tester, int index) async {
  final state = tester.state<ScrollableState>(
    find
        .descendant(of: find.byType(DeckSheet), matching: find.byType(Scrollable))
        .first,
  );
  final slide = tester
      .widgetList<SlideSheet>(find.byType(SlideSheet))
      .first
      .slide;
  state.position.jumpTo(deckExtentFor(slide) * index);
  await settle(tester);
}

void main() {
  group('a deck on the bench', () {
    testWidgets('lays one slide out per slide, in the deck s order', (
      tester,
    ) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);

      expect(find.byType(DeckSheet), findsOneWidget);
      expect(store.isDeck, isTrue);
      expect(store.slides.length, 6);
      // The bench is a list, so only the slides near the top are built.
      final built = tester.widgetList<SlideSheet>(find.byType(SlideSheet));
      expect(built, isNotEmpty);
      expect(built.first.slide.title, 'Press Day Briefing');
    });

    testWidgets('counts in slides, not in a share of the deck', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);

      expect(store.positionLabel, '1 / 6');
      expect(tester.widget<FolioChip>(find.byType(FolioChip)).label, '1 / 6');

      await _benchTo(tester, 3);
      expect(store.position, 3);
      expect(store.positionLabel, '4 / 6');
    });

    testWidgets('opens where it was left, on its first frame', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      store.position = 4;
      await pumpScreen(tester, _reader(store));
      await tester.pump();

      // No settle: a bench that had to be nudged into place after a frame is a
      // bench a reader sees jump.
      final state = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(DeckSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(state.position.pixels, greaterThan(0));
      expect(store.position, 4);
      await settle(tester);
    });

    testWidgets('marks the fore edge once per slide', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      final body = DeckBody(
        store: store,
        document: store.document!,
        onPresent: (_) {},
      );
      expect(body.unitCount, 6);
      expect(body.foreEdgeMarks.length, 6);
      expect(body.foreEdgeMarks.first, 0);
      expect(body.foreEdgeMarks.last, 1);
    });

    testWidgets('a slide keeps its own shape, whatever it is drawn at', (
      tester,
    ) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);

      final slide = store.slides.first;
      final box = tester.getSize(find.byType(SlideSheet).first);
      expect(box.width / box.height, closeTo(slide.width / slide.height, 0.01));
    });

    testWidgets('the back of the sheet carries what the room never saw', (
      tester,
    ) async {
      final store = await storeFor(kPressDayBriefing);
      final body = DeckBody(
        store: store,
        document: store.document!,
        onPresent: (_) {},
      );
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(builder: body.buildBack),
        ),
      );
      await settle(tester);

      expect(find.text('NOTES'), findsOneWidget);
      expect(
        find.textContaining('docket rule', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('present mode', () {
    Future<DocumentStore> open(WidgetTester tester, {int at = 0}) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: PresentScreen(
            store: store,
            slides: store.slides,
            assets: store.document!.assets,
            titles: <String>[
              for (final section in store.document!.sections) section.title,
            ],
            openAt: at,
          ),
        ),
      );
      await tester.pump();
      return store;
    }

    testWidgets('shows one slide and nothing else', (tester) async {
      await open(tester);
      expect(find.byType(SlideSheet), findsOneWidget);
      // Nothing of the cluster before it is asked for. A presentation with
      // controls parked on it is the thing this mode exists to avoid.
      expect(find.bySemanticsLabel('Leave the presentation'), findsNothing);
      expect(find.bySemanticsLabel('The slide after'), findsNothing);
      await settle(tester);
    });

    testWidgets('a tap brings the controls, and another takes them away', (
      tester,
    ) async {
      await open(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);

      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      expect(find.bySemanticsLabel('Leave the presentation'), findsOneWidget);
      expect(find.bySemanticsLabel('Slide 1, go to a slide'), findsOneWidget);

      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      expect(find.bySemanticsLabel('Leave the presentation'), findsNothing);
    });

    testWidgets('the controls go on their own if they are not used', (
      tester,
    ) async {
      await open(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      expect(find.bySemanticsLabel('Leave the presentation'), findsOneWidget);

      await pumpMs(tester, kPresentClusterHold.inMilliseconds + 20);
      await settle(tester);
      expect(find.bySemanticsLabel('Leave the presentation'), findsNothing);
    });

    testWidgets('stepping on moves the slide and the reading with it', (
      tester,
    ) async {
      final store = await open(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('The slide after'));
      await settle(tester);
      expect(store.position, 1);

      await tester.tap(find.bySemanticsLabel('The slide before'));
      await settle(tester);
      expect(store.position, 0);
    });

    testWidgets('a swipe does the same thing as the chevron', (tester) async {
      final store = await open(tester);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 900);
      await settle(tester);
      expect(store.position, 1);
    });

    testWidgets('the number opens the list of slides, by their own titles', (
      tester,
    ) async {
      final store = await open(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Slide 1, go to a slide'));
      await settle(tester);
      expect(find.text('The run in numbers'), findsOneWidget);

      await tester.tap(find.text('The run in numbers'));
      await settle(tester);
      expect(store.position, 2);
    });

    testWidgets('it opens at the slide it was asked for', (tester) async {
      final store = await open(tester, at: 4);
      expect(find.byType(SlideSheet), findsOneWidget);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      expect(find.text('5'), findsOneWidget);
      expect(store.position, 4);
    });
  });

  group('the way into present mode and out again', () {
    testWidgets('a slide on the bench opens the presentation at it', (
      tester,
    ) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);

      await tester.tap(find.byType(SlideCard).first);
      await settle(tester);
      expect(find.byType(PresentScreen), findsOneWidget);
      expect(find.byType(DeckSheet), findsNothing);
    });

    testWidgets('leaving comes back to the reader, on the slide it ended on', (
      tester,
    ) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.tap(find.byType(SlideCard).first);
      await settle(tester);

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 900);
      await settle(tester);
      expect(store.position, 1);

      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Leave the presentation'));
      await settle(tester);

      expect(find.byType(PresentScreen), findsNothing);
      expect(find.byType(DeckSheet), findsOneWidget);
      expect(store.position, 1);
    });
  });

  group('the deck as it looks', () {
    testWidgets('deck__bench', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await precacheImages(tester);
      await capture(tester, 'deck__bench');
    });

    testWidgets('deck__back', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await _benchTo(tester, 4);
      final body = DeckBody(
        store: store,
        document: store.document!,
        onPresent: (_) {},
      );
      await pumpScreen(
        tester,
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(builder: body.buildBack),
        ),
      );
      await settle(tester);
      await capture(tester, 'deck__back');
    });

    testWidgets('present__slide', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.tap(find.byType(SlideCard).first);
      await settle(tester);
      await precacheImages(tester);
      await capture(tester, 'present__slide');
    });

    testWidgets('present__cluster', (tester) async {
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.tap(find.byType(SlideCard).first);
      await settle(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await settle(tester);
      await capture(tester, 'present__cluster');
    });

    testWidgets('present__cluster_t0080', (tester) async {
      // Half way out of the blob: the pill has stretched and the way out is
      // still on its neck. If the goo ever stops being goo, this is the frame
      // that says so.
      final store = await storeFor(kPressDayBriefing);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.tap(find.byType(SlideCard).first);
      await settle(tester);
      await pumpMs(tester, kPresentNoticeHold.inMilliseconds + 20);
      await tester.tapAt(const Offset(201, 300));
      await pumpMs(tester, 80);
      await capture(tester, 'present__cluster_t0080');
      await settle(tester);
    });
  });
}
