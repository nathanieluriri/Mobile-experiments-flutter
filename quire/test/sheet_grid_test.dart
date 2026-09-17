import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/screens/reader/bodies/sheet_geometry.dart';
import 'package:quire/screens/reader/bodies/sheet_grid.dart';
import 'package:quire/screens/reader/bodies/spine_table.dart' show SheetCell;
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';

import 'support/golden.dart';

DocCell _cell(String text, {int colSpan = 1, bool merged = false}) => DocCell(
  <DocBlock>[
    ParagraphBlock(<DocSpan>[DocSpan(text)]),
  ],
  colSpan: colSpan,
  merged: merged,
);

/// A grid [columns] wide and [rows] deep, named by its own address so a test
/// can read a cell off a golden and know where it came from.
TableBlock _grid({
  int columns = 8,
  int rows = 40,
  int frozenRows = 1,
  int frozenColumns = 0,
}) => TableBlock(
  <DocRow>[
    for (var r = 0; r < rows; r++)
      DocRow(<DocCell>[
        for (var c = 0; c < columns; c++)
          _cell(r == 0 ? 'Column ${columnName(c)}' : '${columnName(c)}${r + 1}'),
      ], header: r == 0),
  ],
  columns: <DocColumn>[for (var c = 0; c < columns; c++) const DocColumn()],
  frozenRows: frozenRows,
  frozenColumns: frozenColumns,
  grid: true,
);

String columnName(int index) => String.fromCharCode(0x41 + index);

Widget _app(
  TableBlock table, {
  SheetCell? selected,
  ValueChanged<SheetCell>? onSelect,
  SheetCell? reveal,
  bool locked = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: ColoredBox(
    color: AppColors.ground,
    child: SheetGrid(
      table: table,
      selected: selected,
      reveal: reveal,
      locked: locked,
      onSelect: onSelect ?? (_) {},
    ),
  ),
);

void main() {
  group('where a sheet says its columns and rows are', () {
    test('a file that states nothing gets the reader own measures', () {
      final geometry = SheetGeometry.of(_grid(columns: 3, rows: 5));
      expect(geometry.columnCount, 3);
      expect(geometry.rowCount, 5);
      expect(geometry.widthOf(0), kGridColumnWidth);
      expect(geometry.heightOf(0), kGridRowHeight);
      expect(geometry.size.width, kGridColumnWidth * 3);
      expect(geometry.size.height, kGridRowHeight * 5);
    });

    test('a file that states its own is held to something readable', () {
      final table = TableBlock(
        <DocRow>[
          DocRow(<DocCell>[_cell('a')], height: 4000),
          DocRow(<DocCell>[_cell('b')], height: 48),
        ],
        columns: const <DocColumn>[DocColumn(width: 9000)],
        grid: true,
      );
      final geometry = SheetGeometry.of(table);
      expect(geometry.widthOf(0), kGridColumnMax);
      expect(geometry.heightOf(0), kGridRowMax);
      expect(geometry.heightOf(1), 48);
    });

    test('a point on the sheet names the cell under it', () {
      final geometry = SheetGeometry.of(_grid());
      expect(geometry.columnAt(0), 0);
      expect(geometry.columnAt(kGridColumnWidth - 1), 0);
      expect(geometry.columnAt(kGridColumnWidth), 1);
      expect(geometry.rowAt(kGridRowHeight * 3 + 2), 3);
      // Past the end is the last one rather than nothing, so a finger off the
      // edge of a short sheet still lands somewhere.
      expect(geometry.columnAt(100000), 7);
    });

    test('a merged cell is one cell, wherever in it you touch', () {
      final table = TableBlock(
        <DocRow>[
          DocRow(<DocCell>[
            _cell('Title', colSpan: 3),
            _cell('', merged: true),
            _cell('', merged: true),
          ]),
          DocRow(<DocCell>[_cell('a'), _cell('b'), _cell('c')]),
        ],
        grid: true,
      );
      final geometry = SheetGeometry.of(table);
      expect(geometry.anchorOf(table, const SheetCell(0, 2)),
          const SheetCell(0, 0));
      final rect = geometry.rectOf(table, const SheetCell(0, 2));
      expect(rect.left, 0);
      expect(rect.width, kGridColumnWidth * 3);
    });

    test('what the file froze is held out of what can be pushed', () {
      final geometry = SheetGeometry.of(
        _grid(frozenRows: 2, frozenColumns: 1),
      );
      expect(geometry.frozenRows, 2);
      expect(geometry.frozenColumns, 1);
      expect(geometry.frozenHeight, kGridRowHeight * 2);
      expect(geometry.frozenWidth, kGridColumnWidth);
    });
  });

  group('the grid under a finger', () {
    testWidgets('goes both ways at once and holds its bands', (tester) async {
      await pumpScreen(tester, _app(_grid()));
      await settle(tester);

      // A is at the left, 1 is at the top, and both are where the file put
      // them.
      expect(find.byType(SheetGrid), findsOneWidget);
      await capture(tester, 'sheet__grid');

      await tester.drag(
        find.byType(SheetGrid),
        const Offset(-160, -200),
        warnIfMissed: false,
      );
      await settle(tester);
      await capture(tester, 'sheet__grid_pushed');
    });

    testWidgets('a lock holds it where it is', (tester) async {
      await pumpScreen(tester, _app(_grid(), locked: true));
      await settle(tester);
      await tester.drag(
        find.byType(SheetGrid),
        const Offset(-160, -200),
        warnIfMissed: false,
      );
      await settle(tester);
      await capture(tester, 'sheet__grid');
    });

    testWidgets('a tap names the cell under it', (tester) async {
      SheetCell? chosen;
      await pumpScreen(
        tester,
        _app(_grid(), onSelect: (cell) => chosen = cell),
      );
      await settle(tester);

      final grid = tester.getRect(find.byType(SheetGrid));
      await tester.tapAt(
        grid.topLeft +
            const Offset(
              kRowHeaderWidth + kGridColumnWidth + 10,
              kGridHeaderHeight + kGridRowHeight * 2 + 6,
            ),
      );
      await tester.pump();
      expect(chosen, const SheetCell(2, 1));
    });

    testWidgets('the ring travels to the cell rather than jumping', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        _app(_grid(), selected: const SheetCell(1, 0)),
      );
      await settle(tester);
      await capture(tester, 'sheet__grid_ringed');

      await pumpScreen(
        tester,
        _app(_grid(), selected: const SheetCell(4, 2)),
      );
      await tester.pump();
      await pumpMs(tester, kGridRingMove.inMilliseconds ~/ 2);
      await capture(tester, 'sheet__grid_ring_moving');
      await settle(tester);
    });
  });
}
