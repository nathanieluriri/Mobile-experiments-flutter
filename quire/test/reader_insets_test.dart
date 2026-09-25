import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/bodies/pdf_body.dart';
import 'package:quire/screens/reader/bodies/prose_body.dart';
import 'package:quire/screens/reader/reader_chrome.dart';
import 'package:quire/screens/reader/reader_screen.dart';
import 'package:quire/theme/metrics.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// A phone whose status bar and gesture bar are both shorter than the ones
/// the design was drawn around.
const _android = Phone('Android', Size(402, 874), top: 24, bottom: 16);

Future<void> _pumpPdf(WidgetTester tester, Phone phone) async {
  final store = await storeFor(kFieldGuide);
  final pages = PdfPages.open(await documentBytes(kFieldGuide));
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => PdfBody(store: store, pages: pages),
      ),
    ),
    phone: phone,
  );
  await settle(tester);
}

Future<void> _pumpProse(WidgetTester tester, Phone phone) async {
  final store = await storeFor(kHouseStyle);
  final document = await parsedDocument(kHouseStyle);
  await pumpScreen(
    tester,
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ReaderScreen(
        store: store,
        bodyBuilder: (context) => ProseBody(store: store, document: document),
      ),
    ),
    phone: phone,
  );
  await tester.pump();
  await precacheImages(tester);
  await settle(tester);
}

double _hidden(WidgetTester tester) =>
    tester.widget<ReaderChrome>(find.byType(ReaderChrome)).hidden;

/// Puts the band away with a tap on the page, the way a reader would.
Future<void> _bandAway(WidgetTester tester) async {
  await tester.tapAt(const Offset(kScreenWidth / 2, 500));
  await settle(tester);
  expect(_hidden(tester), 1);
}

void main() {
  for (final phone in const <Phone>[kPhone, _android]) {
    group('on a phone with a ${phone.top} point status bar', () {
      testWidgets('the first page starts under the band, in or out', (
        tester,
      ) async {
        await _pumpPdf(tester, phone);
        final first = find.byType(PdfPageView).first;
        expect(tester.getTopLeft(first).dy, phone.top + kHeadBandHeight);

        // The band leaving uncovers the ground above the page rather than
        // moving the page under the reader's eye.
        await _bandAway(tester);
        expect(tester.getTopLeft(first).dy, phone.top + kHeadBandHeight);
      });

      testWidgets('the pages stop clear of the gesture bar', (tester) async {
        await _pumpPdf(tester, phone);
        final strip = tester.widget<ListView>(find.byType(ListView).first);
        expect(
          strip.padding,
          EdgeInsets.only(
            top: phone.top + kHeadBandHeight,
            bottom: phone.bottom + 8,
          ),
        );
      });

      testWidgets('the first line of prose starts under the band, in or out', (
        tester,
      ) async {
        await _pumpProse(tester, phone);
        final column = find.byType(ProseColumn);
        final top = phone.top + kHeadBandHeight + kSheetPadding;
        expect(tester.getTopLeft(column).dy, top);

        await _bandAway(tester);
        expect(tester.getTopLeft(column).dy, top);
      });

      testWidgets('prose stops clear of the gesture bar', (tester) async {
        await _pumpProse(tester, phone);
        final scroll = tester.widget<SingleChildScrollView>(
          find
              .ancestor(
                of: find.byType(ProseColumn),
                matching: find.byType(SingleChildScrollView),
              )
              .first,
        );
        expect(
          scroll.padding,
          EdgeInsets.only(
            top: phone.top + kHeadBandHeight + kSheetPadding,
            bottom: phone.bottom + 8 + kSheetPadding,
          ),
        );
      });
    });
  }
}
