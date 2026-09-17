import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/model/document.dart';
import 'package:quire/painting/grid_painter.dart';
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
          _cell(
            r == 0 ? 'Column ${columnName(c)}' : '${columnName(c)}${r + 1}',
          ),
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
  SheetReveal? reveal,
  bool locked = false,
  void Function(Offset pan, int topRow, bool byHand)? onPanned,
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
      onPanned: onPanned,
    ),
  ),
);

/// The painter for the grid's cells, which is where the ring and the lit
/// stretch of the bands are handed down, frame by frame.
GridPainter _cells(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GridPainter>()
    .firstWhere((painter) => painter.pane == GridPane.cells);

/// How far the furthest edge of [a] is from the same edge of [b].
double _furthestEdge(Rect a, Rect b) => <double>[
  (a.left - b.left).abs(),
  (a.top - b.top).abs(),
  (a.right - b.right).abs(),
  (a.bottom - b.bottom).abs(),
].reduce(math.max);

/// Every frame of a journey, sixteen milliseconds apart, as the painter was
/// handed it.
Future<List<GridPainter>> _frames(WidgetTester tester, Duration journey) async {
  final seen = <GridPainter>[];
  for (var ms = 0; ms <= journey.inMilliseconds + 64; ms += 16) {
    await tester.pump(const Duration(milliseconds: 16));
    seen.add(_cells(tester));
  }
  return seen;
}

/// The largest step any edge of a travelling rectangle takes between two
/// frames where it is shown, and the last step it takes onto its resting
/// place.
({double largest, double last}) _steps(List<Rect?> rects) {
  var largest = 0.0;
  var last = 0.0;
  for (var i = 1; i < rects.length; i++) {
    final a = rects[i - 1];
    final b = rects[i];
    if (a == null || b == null) continue;
    final step = _furthestEdge(a, b);
    largest = math.max(largest, step);
    if (step > 0) last = step;
  }
  return (largest: largest, last: last);
}

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
      final table = TableBlock(<DocRow>[
        DocRow(<DocCell>[
          _cell('Title', colSpan: 3),
          _cell('', merged: true),
          _cell('', merged: true),
        ]),
        DocRow(<DocCell>[_cell('a'), _cell('b'), _cell('c')]),
      ], grid: true);
      final geometry = SheetGeometry.of(table);
      expect(
        geometry.anchorOf(table, const SheetCell(0, 2)),
        const SheetCell(0, 0),
      );
      final rect = geometry.rectOf(table, const SheetCell(0, 2));
      expect(rect.left, 0);
      expect(rect.width, kGridColumnWidth * 3);
    });

    test('what the file froze is held out of what can be pushed', () {
      final geometry = SheetGeometry.of(_grid(frozenRows: 2, frozenColumns: 1));
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
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(1, 0)));
      await settle(tester);
      await capture(tester, 'sheet__grid_ringed');

      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(4, 2)));
      await tester.pump();
      // Setting off: the ring draws in to the goo gathering out of the cell,
      // and the lit letter and number start to crawl.
      await pumpMs(tester, kGridRingMove.inMilliseconds * 10 ~/ 100);
      await capture(tester, 'sheet__grid_ring_gathering');
      // Early: the goo is crossing, and there is no ring anywhere, because
      // the choice is in transit.
      await pumpMs(tester, kGridRingMove.inMilliseconds * 25 ~/ 100);
      await capture(tester, 'sheet__grid_ring_crossing');
      // Late: the goo has reached the new cell and the ring opens out of it.
      await pumpMs(tester, kGridRingMove.inMilliseconds * 35 ~/ 100);
      await capture(tester, 'sheet__grid_ring_moving');
      await settle(tester);
      await capture(tester, 'sheet__grid_ring_arrived');
    });

    testWidgets('a first choice condenses onto its cell', (tester) async {
      await pumpScreen(tester, _app(_grid()));
      await settle(tester);
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(3, 1)));
      await tester.pump();
      await pumpMs(tester, kGridRingAppear.inMilliseconds * 20 ~/ 100);
      await capture(tester, 'sheet__grid_ring_condensing');
      await pumpMs(tester, kGridRingAppear.inMilliseconds * 35 ~/ 100);
      await capture(tester, 'sheet__grid_ring_opening');
      await settle(tester);
      expect(_cells(tester).ring, isNotNull);
      expect(_cells(tester).ringStrength, 1);
    });

    testWidgets('a choice let go dries up where it was', (tester) async {
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(3, 1)));
      await settle(tester);
      await pumpScreen(tester, _app(_grid()));
      await tester.pump();
      await pumpMs(tester, kGridRingLeave.inMilliseconds * 30 ~/ 100);
      await capture(tester, 'sheet__grid_ring_drawing_in');
      await pumpMs(tester, kGridRingLeave.inMilliseconds * 35 ~/ 100);
      await capture(tester, 'sheet__grid_ring_drying');
      await settle(tester);
      expect(_cells(tester).ring, isNull);
      expect(_cells(tester).lit, isNull);
    });
  });

  group('the choice never snaps', () {
    testWidgets('the ring opens and comes to rest without a jump', (
      tester,
    ) async {
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(1, 0)));
      await settle(tester);
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(6, 3)));
      await tester.pump();
      final frames = await _frames(tester, kGridRingMove);
      final rings = <Rect?>[for (final frame in frames) frame.ring];
      final steps = _steps(rings);
      // A ring that turned up at full size, or was cut off still opening and
      // jumped to its cell, would take one step as big as the cell.
      expect(steps.largest, lessThan(kGridColumnWidth / 4));
      // It eases into its cell: the step onto its resting place is too small
      // to see.
      expect(steps.last, lessThan(0.5));
      expect(rings.last, isNotNull);
      for (final frame in frames) {
        expect(frame.ringStrength, inInclusiveRange(0, 1));
      }
    });

    testWidgets('the lit letter crawls, leading edge first', (tester) async {
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(2, 0)));
      await settle(tester);
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(2, 3)));
      await tester.pump();
      final frames = await _frames(tester, kGridRingMove);
      final spans = <Rect?>[for (final frame in frames) frame.lit];
      expect(spans, everyElement(isNotNull));
      final steps = _steps(spans);
      // Three columns in one jump would be a step of three columns.
      expect(steps.largest, lessThan(kGridColumnWidth / 2));
      expect(steps.last, lessThan(0.5));
      // Going right, the right edge sets off first: somewhere on the way the
      // lit stretch is longer than the column it left.
      final widest = spans.map((span) => span!.width).reduce(math.max);
      expect(widest, greaterThan(kGridColumnWidth * 1.5));
      // And it only ever goes the way the choice went.
      for (var i = 1; i < spans.length; i++) {
        expect(spans[i]!.left, greaterThanOrEqualTo(spans[i - 1]!.left));
        expect(spans[i]!.right, greaterThanOrEqualTo(spans[i - 1]!.right));
      }
    });

    testWidgets('a second tap on the way bends the journey', (tester) async {
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(1, 0)));
      await settle(tester);
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(8, 2)));
      await tester.pump();
      await pumpMs(tester, kGridRingMove.inMilliseconds * 40 ~/ 100);
      final before = _cells(tester).lit!;
      await pumpScreen(tester, _app(_grid(), selected: const SheetCell(3, 5)));
      await tester.pump();
      final after = _cells(tester).lit!;
      // It carries on from where it had got to, not from where it started.
      expect(_furthestEdge(before, after), lessThan(kGridRowHeight));
      await settle(tester);
      expect(_cells(tester).lit, _cells(tester).ring);
    });
  });

  group('a cell asked for', () {
    testWidgets('is glided to rather than cut to', (tester) async {
      final pans = <Offset>[];
      final hands = <bool>[];
      void panned(Offset pan, int topRow, bool byHand) {
        pans.add(pan);
        hands.add(byHand);
      }

      await pumpScreen(tester, _app(_grid(), onPanned: panned));
      await settle(tester);
      await pumpScreen(
        tester,
        _app(
          _grid(),
          reveal: SheetReveal(const SheetCell(30, 6)),
          onPanned: panned,
        ),
      );
      await settle(tester);
      // Many small pushes rather than one, and none of them a hand, so
      // nothing listening for a hand lets go of the cell that asked.
      expect(pans.length, greaterThan(10));
      expect(hands, everyElement(isFalse));
      final whole = pans.last.distance;
      for (var i = 1; i < pans.length; i++) {
        expect((pans[i] - pans[i - 1]).distance, lessThan(whole / 4));
      }
    });

    testWidgets('a run of them is followed in one movement', (tester) async {
      // A thumb on the fore edge asks for a new row every frame. A glide that
      // started over from rest at each one would barely move at all.
      final pans = <Offset>[];
      void panned(Offset pan, int topRow, bool byHand) => pans.add(pan);

      await pumpScreen(tester, _app(_grid(rows: 120), onPanned: panned));
      await settle(tester);
      for (var row = 4; row < 40; row++) {
        await pumpScreen(
          tester,
          _app(
            _grid(rows: 120),
            reveal: SheetReveal(SheetCell(row, 0), toTop: true),
            onPanned: panned,
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final tail = pans.sublist(pans.length - 10);
      final covered = tail.last.dy - tail.first.dy;
      // Keeping up with a row a frame, give or take the lag of the spring.
      expect(covered / 9, greaterThan(kGridRowHeight * 0.6));
      // Never back the way it came, to within the rounding of a double.
      for (var i = 1; i < pans.length; i++) {
        expect(pans[i].dy, greaterThanOrEqualTo(pans[i - 1].dy - 1e-9));
      }
      await settle(tester);
      // And it comes to rest with the last row asked for at the top.
      expect(pans.last.dy, kGridRowHeight * 39 - kGridRowHeight);
    });

    testWidgets('a jump puts its row at the top', (tester) async {
      final pans = <Offset>[];
      await pumpScreen(tester, _app(_grid(), onPanned: (pan, _, _) {}));
      await settle(tester);
      await pumpScreen(
        tester,
        _app(
          _grid(),
          reveal: SheetReveal(const SheetCell(12, 0), toTop: true),
          onPanned: (pan, _, _) => pans.add(pan),
        ),
      );
      await settle(tester);
      // Row 13 sits under the frozen header row, which is one row tall.
      expect(pans.last.dy, kGridRowHeight * 12 - kGridRowHeight);
    });
  });
}
