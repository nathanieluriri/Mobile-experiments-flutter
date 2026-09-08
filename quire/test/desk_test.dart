import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/pdf/document.dart';
import 'package:quire/screens/desk/desk_colophon.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/document_card.dart';
import 'package:quire/screens/desk/shelf_chips.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// The three documents the desk has been read from, and the one that carries a
/// signature.
///
/// Fixed rather than incidental, because READING and SIGNED are shelves and a
/// shelf golden is only worth looking at if you know why each card is on it.
const kReadFileNames = <String>[kFieldGuide, kHouseStyle, kSubscribers];
const kSignedFileName = kFieldGuide;

/// A library with every bundled document parsed, so the desk prints real page,
/// row and word counts rather than the literals from the manifest.
Future<LibraryStore> deskStore() async {
  final store = LibraryStore();
  for (final entry in libraryEntries) {
    final bytes = await documentBytes(entry.fileName);
    final document = store.storeFor(entry)..loadFrom(bytes);
    if (document.isPdf) {
      document.pdfPageCount = PdfFile.open(bytes).pageCount;
    }
  }
  for (final name in kReadFileNames) {
    final document = store.storeFor(entryFor(name));
    document.position = ((document.unitCount - 1) * 0.38).round();
  }
  store.storeFor(entryFor(kSignedFileName)).placeSignature(
        const PlacedSignature(
          pageIndex: 1,
          rect: ui.Rect.fromLTWH(120, 600, 180, 60),
          strokes: <List<ui.Offset>>[
            <ui.Offset>[ui.Offset(0, 1), ui.Offset(0.5, 0), ui.Offset(1, 1)],
          ],
        ),
      );
  return store;
}

/// The app with the desk behind its one route.
Widget deskApp(
  LibraryStore store, {
  void Function(LibraryEntry entry, Rect cardRect)? onOpen,
}) =>
    App(
      routes: <String, WidgetBuilder>{
        kDeskRoute: (context) => DeskScreen(store: store, onOpen: onOpen),
      },
    );

void main() {
  test('counts are grouped so a five digit number reads at a glance', () {
    expect(groupedNumber(0), '0');
    expect(groupedNumber(72), '72');
    expect(groupedNumber(1410), '1,410');
    expect(groupedNumber(20966), '20,966');
    expect(groupedNumber(1234567), '1,234,567');
  });

  test('a card with nothing parsed behind it claims no count', () async {
    final entry = entryFor(kPressLease);
    expect(cardMeta(entry, null), 'PDF · 20 KB');
    expect(cardBackLines(entry, null), <String>[
      'press-lease.pdf',
      '20,966 bytes',
      'never opened',
    ]);
  });

  test('a parsed card prints its real shape, front and back', () async {
    final store = await deskStore();
    final entry = entryFor(kPressLease);
    final document = store.storeFor(entry);
    expect(document.pdfPageCount, 2);
    expect(cardMeta(entry, document), 'PDF · 2 PAGES · 20 KB');
    expect(cardBackLines(entry, document), <String>[
      'press-lease.pdf',
      '20,966 bytes',
      '2 pages',
      'never opened',
    ]);

    final guide = store.storeFor(entryFor(kFieldGuide));
    expect(guide.pdfPageCount, 6);
    expect(cardMeta(entryFor(kFieldGuide), guide), 'PDF · 6 PAGES · 306 KB');
    expect(cardBackLines(entryFor(kFieldGuide), guide), <String>[
      'field-guide-to-paper.pdf',
      '313,458 bytes',
      '6 pages',
      'signed',
      'left at ${guide.positionLabel}',
    ]);

    final rows = store.storeFor(entryFor(kSubscribers));
    expect(cardUnits(entryFor(kSubscribers), rows)!.upper, 'ROWS');
    final words = store.storeFor(entryFor(kBinderyNotes));
    expect(cardUnits(entryFor(kBinderyNotes), words)!.upper, 'WORDS');
  });

  test('the shelves count what they hold, and the colophon counts the desk',
      () async {
    final store = await deskStore();
    expect(store.countOn(Shelf.all), 6);
    expect(store.countOn(Shelf.reading), kReadFileNames.length);
    expect(store.countOn(Shelf.signed), 1);

    final colophon = DeskColophon(
      documents: store.documentCount,
      words: store.wordCount,
      minutes: store.minutes,
    );
    expect(colophon.line.startsWith('6 DOCUMENTS · '), isTrue);
    expect(colophon.line.contains(' WORDS · '), isTrue);
    expect(colophon.line.endsWith(' MINUTES'), isTrue);

    const single = DeskColophon(documents: 1, words: 1, minutes: 1);
    expect(single.line, '1 DOCUMENT · 1 WORD · 1 MINUTE');
    const bare = DeskColophon(documents: 3, words: 0, minutes: 0);
    expect(bare.line, '3 DOCUMENTS');
  });

  test('the desk search matches a title and a format, with no debounce',
      () async {
    final store = await deskStore();
    store.query = 'es';
    expect(
      store.visible.map((entry) => entry.fileName).toList(),
      <String>[kPressLease, kPressRunCosts, kBinderyNotes],
    );
    store.query = 'vellum';
    expect(store.visible, isEmpty);
    store.query = 'csv';
    expect(store.visible.single.fileName, kSubscribers);
  });

  testWidgets('the desk lays out six cards, the shelves and the colophon',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    expect(tester.getTopLeft(find.byType(DeskColophon)).dx, 20);
    await capture(tester, 'desk__six');
  });

  testWidgets('the READING shelf leaves three cards and warm ground',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    store.shelf = Shelf.reading;
    await settle(tester);
    await capture(tester, 'desk__three');
  });

  testWidgets('the wordmark collapses into the bar as the list goes under it',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    // The collapse is only reachable if the list is taller than the viewport,
    // which is what kDeskListBottomPadding is there to guarantee.
    expect(position.maxScrollExtent, greaterThan(58));
    position.jumpTo(58);
    await tester.pump();
    await capture(tester, 'desk__scrolled');
  });

  testWidgets('a shelf with nothing on it stands down rather than lying',
      (tester) async {
    // Nothing parsed and nothing read, so two of the three shelves are empty.
    final store = LibraryStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    expect(store.countOn(Shelf.reading), 0);
    expect(store.countOn(Shelf.signed), 0);
    for (final shelf in <Shelf>[Shelf.reading, Shelf.signed]) {
      final faded = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text(shelfLabel(shelf)),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(faded.opacity, kEmptyShelfOpacity);
    }
    await tester.tap(find.text(shelfLabel(Shelf.reading)));
    await settle(tester);
    expect(store.shelf, Shelf.all);
  });

  testWidgets('an empty desk shows the mark, the two lines and the pill',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    for (final entry in libraryEntries) {
      store.remove(entry);
    }
    await settle(tester);
    expect(store.entries, isEmpty);
    await capture(tester, 'desk__empty');
  });
}
