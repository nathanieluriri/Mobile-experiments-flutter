import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/bodies/prose_body.dart';
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/find/find_layer.dart';
import 'package:quire/screens/reader/folio_chip.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/screens/sign/placement_layer.dart';
import 'package:quire/screens/sign/sign_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

void main() {
  group('the reader picks the body its document asks for', () {
    testWidgets('a page file gets the page engine, counted before it is run', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      expect(find.byType(PdfPageBlock), findsOneWidget);
      // The count comes off the page tree as the reader opens, so the chip and
      // the fore edge agree before a single content stream has been run.
      expect(store.pdfPageCount, 6);
      expect(
        tester.widget<FolioChip>(find.byType(FolioChip)).label,
        '1 / 6',
      );
    });

    testWidgets('a Markdown file gets prose, with its own source behind it', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      expect(find.byType(ProseSheet), findsOneWidget);
      // The back of a Markdown sheet is the file's own text, and nothing but
      // the route can decode it, so the body is asked what it was handed.
      final body = tester
          .widget<ReaderScreen>(find.byType(ReaderScreen))
          .bodyBuilder(tester.element(find.byType(ReaderScreen)));
      expect(body, isA<ProseBody>());
      expect((body as ProseBody).source, contains('#'));
      expect(
        tester.widget<FolioChip>(find.byType(FolioChip)).label.endsWith('%'),
        isTrue,
      );
    });

    testWidgets('a workbook gets the grid', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      expect(find.byType(SheetView), findsWidgets);
    });
  });

  testWidgets('a card on the desk opens onto a real page', (tester) async {
    await pumpScreen(tester, const App());
    await settle(tester);
    await tester.tapAt(const Offset(201, 300));
    await settle(tester);

    // The desk hands the reader a document and the reader gives it the body
    // its format asks for, with no route registered by hand anywhere.
    expect(find.byType(ReaderHost), findsOneWidget);
    expect(find.byType(PdfPageBlock), findsOneWidget);
  });

  group('find over a real document', () {
    testWidgets('the pill opens the field, and a step moves the reader', (
      tester,
    ) async {
      final store = await storeFor(kBinderyNotes);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);
      expect(find.byType(FindLayer), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'grain');
      await settle(tester);
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.matches.length, 11);
      expect(reader.liveMatch, isNotNull);

      // Typing leaves the document where it was: the fore edge is the map and
      // the chevrons are the step.
      expect(store.position, 0);
      await tester.tap(find.bySemanticsLabel('Next match'));
      await settle(tester);
      expect(store.position, greaterThan(0));
    });

    testWidgets('a page file is indexed from its own text layer', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Find in document'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'paper');
      await settle(tester);

      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.matches, isNotEmpty);
      expect(reader.matchCounts.length, 6, reason: 'one count per page');
    });
  });

  group('a signature arriving from the pad', () {
    testWidgets('goes up as a placement layer over the page it belongs to', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      await pumpScreen(
        tester,
        _host(store, placing: SignatureMark.of(strokeAcross())),
      );
      await settle(tester);

      expect(find.byType(PlacementLayer), findsOneWidget);
      expect(store.signed, isFalse, reason: 'nothing is set until it lands');
    });

    testWidgets('holds the fore edge back while it is being placed', (
      tester,
    ) async {
      final store = await storeFor(kPressLease);
      await pumpScreen(
        tester,
        _host(store, placing: SignatureMark.of(strokeAcross())),
      );
      await settle(tester);

      // A tap inside the strip would open the riffle over the page the mark is
      // being set on, which is the one layer that must not appear now.
      await tester.tapAt(const Offset(kForeEdgeLeft + 4, 400));
      await settle(tester);
      expect(find.byType(PlacementLayer), findsOneWidget);
    });

    testWidgets('the pad hands its mark to the reader', (tester) async {
      await pumpScreen(tester, const App());
      await settle(tester);

      // The route the desk's SIGN action pushes, driven straight so the flow
      // between the two screens is what is under test rather than the peel.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final store = DocumentStore.ready(
        entryFor(kPressLease),
        await documentBytes(kPressLease),
      );
      unawaited(navigator.pushNamed(kSignRoute, arguments: store));
      await settle(tester);
      expect(find.byType(SignScreen), findsOneWidget);

      // One stroke across the pad, then the commit pill.
      var elapsed = Duration.zero;
      final gesture = await tester.createGesture();
      await gesture.down(const Offset(120, 300), timeStamp: elapsed);
      for (final point in const <Offset>[
        Offset(180, 262),
        Offset(240, 306),
        Offset(300, 270),
      ]) {
        elapsed += const Duration(milliseconds: 16);
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(point, timeStamp: elapsed);
      }
      await gesture.up(timeStamp: elapsed);
      await settle(tester);
      await tester.tap(find.text('Place on page'));
      await settle(tester);

      expect(find.byType(SignScreen), findsNothing);
      expect(find.byType(ReaderHost), findsOneWidget);
      expect(find.byType(PlacementLayer), findsOneWidget);
    });
  });
}

/// The reader, assembled the way the app assembles it.
Widget _host(DocumentStore store, {SignatureMark? placing}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store, placing: placing),
);

/// One stroke, enough to make a mark out of.
List<InkStroke> strokeAcross() => <InkStroke>[
  InkStroke.fromSamples(
    const <Offset>[Offset(0, 20), Offset(40, 4), Offset(90, 24)],
    const <Duration>[
      Duration.zero,
      Duration(milliseconds: 40),
      Duration(milliseconds: 90),
    ],
  ),
];

/// A push whose result nobody is waiting for.
void unawaited(Future<void> future) {}
