import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/reader/dog_ears_sheet.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _host(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('What can be done with this document'));
  await settle(tester);
}

void main() {
  group('what a dog ear is called', () {
    test('a page in a PDF, a row in a sheet, a share of prose', () async {
      final pdf = await storeFor(kFieldGuide);
      expect(pdf.unitName(3), 'Page 4');
      final grid = await storeFor(kSubscribers);
      expect(grid.unitName(23), 'Row 24');
      final prose = await storeFor(kBinderyNotes);
      expect(prose.unitName(prose.unitCount - 1), '100% through');
    });
  });

  group('the list of dog ears', () {
    testWidgets('is not offered while there are none', (tester) async {
      final store = await storeFor(kFieldGuide);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _openMenu(tester);
      expect(find.text('Dog ears'), findsNothing);
    });

    testWidgets('lists them in reading order and goes to the one picked', (
      tester,
    ) async {
      final store = await storeFor(kFieldGuide);
      store
        ..toggleDogEar(4)
        ..toggleDogEar(1);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Dog ears'));
      await settle(tester);

      expect(find.byType(DogEarsSheet), findsOneWidget);
      final second = tester.getTopLeft(find.text('Page 2')).dy;
      final fifth = tester.getTopLeft(find.text('Page 5')).dy;
      expect(second, lessThan(fifth));
      await capture(tester, 'reader__dog_ears');

      await tester.tap(find.text('Page 5'));
      await settle(tester);
      expect(find.byType(DogEarsSheet), findsNothing);
      expect(store.position, 4);
    });

    testWidgets('lets a corner go without going there', (tester) async {
      final store = await storeFor(kFieldGuide);
      store
        ..toggleDogEar(2)
        ..toggleDogEar(3);
      await pumpScreen(tester, _host(store));
      await settle(tester);
      await _openMenu(tester);
      await tester.tap(find.text('Dog ears'));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Let go of Page 3'));
      await settle(tester);
      expect(store.dogEared, <int>{3});
      expect(find.text('Page 3'), findsNothing);
      expect(find.byType(DogEarsSheet), findsOneWidget);
      expect(store.position, 0);
    });
  });
}
