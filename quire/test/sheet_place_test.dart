import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/painting/grid_painter.dart';
import 'package:quire/screens/reader/bodies/sheet_body.dart';
import 'package:quire/screens/reader/bodies/sheet_geometry.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/reader_host.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Widget _reader(DocumentStore store) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ReaderHost(store: store),
);

/// How far the sheet has been pushed inside the grid, read off the cells it
/// painted: where that pane starts in the sheet, less the frozen panes held
/// above and beside it.
Offset _pushed(WidgetTester tester, DocumentStore store, [int sheet = 0]) {
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<GridPainter>()
      .where((painter) => painter.pane == GridPane.cells)
      .last;
  final geometry = _geometryOf(store, sheet);
  return painter.offset - Offset(geometry.frozenWidth, geometry.frozenHeight);
}

SheetGeometry _geometryOf(DocumentStore store, int sheet) => SheetGeometry.of(
  store.document!.sections[sheet].blocks.whereType<TableBlock>().first,
);

/// The same document opened again in a later run of the app: a new store,
/// holding nothing but what the desk wrote down.
Future<DocumentStore> _opensAgain(DocumentStore store, String name) async {
  final saved = store.toJson();
  final again = DocumentStore.ready(entryFor(name), await documentBytes(name));
  again.restore(saved);
  return again;
}

void main() {
  group('a workbook comes back where it was left', () {
    testWidgets('on the sheet, the row and the column it was pushed to', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      expect(_pushed(tester, store), Offset.zero);

      await tester.drag(
        find.byType(SheetGrid),
        const Offset(-160, -180),
        warnIfMissed: false,
      );
      await settle(tester);
      final left = _pushed(tester, store);
      expect(left.dx, greaterThan(0));
      expect(left.dy, greaterThan(0));

      // Closed and opened again: the desk wrote the place down with
      // everything else it keeps about the document.
      final again = await _opensAgain(store, kPressRunCosts);
      expect(again.place, isNotNull);
      await pumpScreen(tester, _reader(again));
      await settle(tester);
      expect(_pushed(tester, again).dx, closeTo(left.dx, 0.5));
      expect(_pushed(tester, again).dy, closeTo(left.dy, 0.5));
    });

    testWidgets('on the sheet of a workbook it was left on', (tester) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      SheetController.of(store).sheet = 1;
      await settle(tester);

      final again = await _opensAgain(store, kPressRunCosts);
      await pumpScreen(tester, _reader(again));
      await settle(tester);
      expect(SheetController.of(again).sheet, 1);
    });

    testWidgets('at the row it says it is on, for a place it never kept', (
      tester,
    ) async {
      // What a document read before the place was kept comes back as: the
      // row the desk wrote down, and nothing else.
      final store = await storeFor(kPressRunCosts);
      store.position = 5;
      expect(store.place, isNull);

      await pumpScreen(tester, _reader(store));
      await settle(tester);
      // The row is at the top of the grid, where the folio chip says the
      // reader is, rather than the first row of the sheet.
      final geometry = _geometryOf(store, 0);
      expect(
        _pushed(tester, store).dy,
        closeTo(geometry.topOf(5) - geometry.frozenHeight, 0.5),
      );
      expect(store.position, 5);
    });

    testWidgets('inside the sheet, when the file has since grown shorter', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      store.restore(<String, Object?>{
        'place': <String, Object?>{'sheet': 0, 'across': 20000, 'down': 90000},
      });
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      final geometry = _geometryOf(store, 0);
      // Somewhere in the sheet, not thousands of points past its last row.
      expect(_pushed(tester, store).dy, lessThan(geometry.size.height));
      expect(_pushed(tester, store).dx, lessThan(geometry.size.width));
    });

    testWidgets('and stays where it is when the app is put down and taken up', (
      tester,
    ) async {
      final store = await storeFor(kPressRunCosts);
      await pumpScreen(tester, _reader(store));
      await settle(tester);
      await tester.drag(
        find.byType(SheetGrid),
        const Offset(-120, -300),
        warnIfMissed: false,
      );
      await settle(tester);
      final left = _pushed(tester, store);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);

      expect(_pushed(tester, store).dx, closeTo(left.dx, 0.01));
      expect(_pushed(tester, store).dy, closeTo(left.dy, 0.01));
    });
  });
}
