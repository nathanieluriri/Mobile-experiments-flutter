import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/fore_edge.dart';
import 'package:quire/screens/reader/folio_chip.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/unlock_chip.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _host(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

void main() {
  group('the lock a reader can put on', () {
    test('a document opens with nothing fastened', () async {
      final store = await storeFor(kFieldGuide);
      expect(store.lock, ReaderLock.none);
      expect(store.lock.holdsBack, isFalse);
      expect(store.lock.holdsPage, isFalse);
    });

    test('a page lock holds the way out as well as the page', () async {
      final store = await storeFor(kFieldGuide);
      store.lock = ReaderLock.page;
      expect(store.lock.holdsPage, isTrue);
      expect(store.lock.holdsBack, isTrue);
    });

    test('the way out can be held without the page', () async {
      final store = await storeFor(kFieldGuide);
      store.lock = ReaderLock.back;
      expect(store.lock.holdsBack, isTrue);
      expect(store.lock.holdsPage, isFalse);
    });

    test('fastening tells the reading', () async {
      final store = await storeFor(kFieldGuide);
      var beats = 0;
      store.addListener(() => beats++);
      store.lock = ReaderLock.page;
      expect(beats, 1);
      // Setting the same lock twice is not a change.
      store.lock = ReaderLock.page;
      expect(beats, 1);
    });
  });

  group('a reading locked to its page', () {
    testWidgets('keeps the band, the fore edge and the folio off screen', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      expect(find.byType(ForeEdge), findsOneWidget);
      expect(find.byType(FolioChip), findsOneWidget);

      store.lock = ReaderLock.page;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ForeEdge), findsNothing);
      expect(find.byType(FolioChip), findsNothing);
      // The band is still built, and it is entirely off the top of the screen.
      final band = tester.widget<ReaderChrome>(find.byType(ReaderChrome));
      expect(band.hidden, 1);
    });

    testWidgets('says what it did, once, on the chip that undoes it', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      expect(find.byType(UnlockChip), findsNothing);
      store.lock = ReaderLock.page;
      await tester.pump();
      await tester.pump(kUnlockChipFade);

      final chip = tester.widget<UnlockChip>(find.byType(UnlockChip));
      expect(chip.progress, 1);

      // And then it goes, rather than sitting on the page.
      await tester.pump(kUnlockChipHold);
      await tester.pump(kUnlockChipFade);
      expect(
        tester.widget<UnlockChip>(find.byType(UnlockChip)).progress,
        0,
      );
    });

    testWidgets('a tap on the page asks for the way out again', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.lock = ReaderLock.page;
      await tester.pump();
      await tester.pump(kUnlockChipFade);
      await tester.pump(kUnlockChipHold);
      await tester.pump(kUnlockChipFade);
      expect(
        tester.widget<UnlockChip>(find.byType(UnlockChip)).progress,
        0,
      );

      await tester.tapAt(const Offset(200, 500));
      await tester.pump();
      await tester.pump(kUnlockChipFade);
      expect(
        tester.widget<UnlockChip>(find.byType(UnlockChip)).progress,
        1,
      );
    });

    testWidgets('the chip takes the lock off', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.lock = ReaderLock.page;
      await tester.pump();
      await tester.pump(kUnlockChipFade);

      await tester.tap(find.byType(UnlockChip));
      await tester.pump();
      expect(store.lock, ReaderLock.none);

      await settle(tester);
      expect(find.byType(ForeEdge), findsOneWidget);
      expect(find.byType(FolioChip), findsOneWidget);
    });
  });

  group('a reading with only the way out locked', () {
    testWidgets('takes every bar off the screen, the band included', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      store.lock = ReaderLock.back;
      await tester.pump();
      await settle(tester);

      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 1);
      expect(find.byType(ForeEdge), findsNothing);
      expect(find.byType(FolioChip), findsNothing);
    });

    testWidgets('a tap does not bring the band back, only the chip', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.lock = ReaderLock.back;
      await tester.pump();
      await settle(tester);

      await tester.tapAt(const Offset(200, 500));
      await tester.pump(kUnlockChipFade);
      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 1);
      final chip = tester.widget<UnlockChip>(find.byType(UnlockChip));
      expect(chip.progress, 1);
      expect(chip.label, 'Unlock the reading');
      await settle(tester);
    });

    testWidgets('the chip at the bottom is the way out of the lock', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      store.lock = ReaderLock.back;
      await tester.pump();
      await tester.pump(kUnlockChipFade);

      await tester.tap(find.byType(UnlockChip));
      await tester.pump();
      expect(store.lock, ReaderLock.none);
      await settle(tester);
      expect(find.byType(ForeEdge), findsOneWidget);
    });

    testWidgets('still scrolls, which is what separates it from a page lock', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.lock = ReaderLock.back;
      await tester.pump();
      await settle(tester);

      final list = tester.widget<Scrollable>(find.byType(Scrollable).first);
      expect(list.physics, isNot(isA<NeverScrollableScrollPhysics>()));
    });
  });

  group('the band a tap puts away', () {
    testWidgets('a tap on the page hides it, and another brings it back', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      // It opens showing, at the very top, where there is nothing above the
      // first line to scroll towards.
      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 0);

      await tester.tapAt(const Offset(200, 500));
      await settle(tester);
      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 1);

      await tester.tapAt(const Offset(200, 500));
      await settle(tester);
      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 0);
    });

    testWidgets('a locked page answers a tap with the chip and not the band', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      store.lock = ReaderLock.page;
      await tester.pump();
      await settle(tester);

      await tester.tapAt(const Offset(200, 500));
      await tester.pump(kUnlockChipFade);
      expect(tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden, 1);
      expect(
        tester.widget<UnlockChip>(find.byType(UnlockChip)).progress,
        1,
      );
    });
  });
}
