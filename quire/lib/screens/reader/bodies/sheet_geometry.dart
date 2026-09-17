import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../../../model/document.dart';
import '../../../theme/metrics.dart';
import 'spine_table.dart' show SheetCell, cellAt;

/// Where every column and every row of a sheet sits, in the sheet's own space.
///
/// It is worked out once per sheet and then asked questions: where a cell is,
/// which cell a finger landed on, which rows and columns are worth drawing at
/// a given corner. Keeping it apart from the widget is what lets the grid be
/// tested without a screen, and what keeps a pan from rebuilding anything but
/// the paint.
class SheetGeometry {
  SheetGeometry._(
    this._covered, {
    required this.widths,
    required this.heights,
    required this.lefts,
    required this.tops,
    required this.frozenRows,
    required this.frozenColumns,
  });

  /// Reads [table]'s own widths and heights, falling back to the reader's.
  ///
  /// A file that says nothing about a column gets [kGridColumnWidth], which is
  /// wide enough for a date or a short name at the reading size. A file that
  /// asks for something absurd is held between [kGridColumnMin] and
  /// [kGridColumnMax], because a column three screens wide is a column nobody
  /// can read across and one four points wide is a column nobody can read at
  /// all.
  factory SheetGeometry.of(TableBlock table) {
    final columns = _columnCount(table);
    final widths = <double>[
      for (var c = 0; c < columns; c++)
        (c < table.columns.length ? table.columns[c].width : null)?.clamp(
              kGridColumnMin,
              kGridColumnMax,
            ) ??
            kGridColumnWidth,
    ];
    final heights = <double>[
      for (final row in table.rows)
        row.height?.clamp(kGridRowMin, kGridRowMax) ?? kGridRowHeight,
    ];
    return SheetGeometry._(
      _merges(table, columns),
      widths: widths,
      heights: heights,
      lefts: _running(widths),
      tops: _running(heights),
      frozenRows: _frozenRows(table),
      frozenColumns: table.frozenColumns.clamp(0, columns),
    );
  }

  /// Every cell a merge has swallowed, keyed by its place, with the cell the
  /// merge starts at. Worked out once, so asking where a merge starts is a
  /// lookup and not a search back up the sheet for every cell painted.
  static Map<int, SheetCell> _merges(TableBlock table, int columns) {
    final covered = <int, SheetCell>{};
    for (var r = 0; r < table.rows.length; r++) {
      final cells = table.rows[r].cells;
      for (var c = 0; c < cells.length; c++) {
        final cell = cells[c];
        if (cell.merged) continue;
        final across = math.max(1, cell.colSpan);
        final down = math.max(1, cell.rowSpan);
        if (across == 1 && down == 1) continue;
        for (var rr = r; rr < math.min(table.rows.length, r + down); rr++) {
          for (var cc = c; cc < math.min(columns, c + across); cc++) {
            if (rr == r && cc == c) continue;
            covered[rr * columns + cc] = SheetCell(r, c);
          }
        }
      }
    }
    return covered;
  }

  final Map<int, SheetCell> _covered;

  final List<double> widths;
  final List<double> heights;

  /// Where each column starts, and one more for where the last one ends.
  final List<double> lefts;
  final List<double> tops;

  /// How many rows and columns the file holds still. The band of letters and
  /// the spine of numbers are not counted here: those are the reader's and are
  /// always held.
  final int frozenRows;
  final int frozenColumns;

  int get columnCount => widths.length;
  int get rowCount => heights.length;

  /// The whole grid's size, header band and row spine not counted.
  Size get size => Size(lefts.last, tops.last);

  /// How much of the grid the frozen panes take up, which is the room the
  /// scrolling part does not get.
  double get frozenWidth => frozenColumns == 0 ? 0 : lefts[frozenColumns];
  double get frozenHeight => frozenRows == 0 ? 0 : tops[frozenRows];

  double leftOf(int column) => lefts[column.clamp(0, columnCount)];
  double topOf(int row) => tops[row.clamp(0, rowCount)];
  double widthOf(int column) =>
      column < 0 || column >= columnCount ? 0 : widths[column];
  double heightOf(int row) => row < 0 || row >= rowCount ? 0 : heights[row];

  /// Where [cell] sits in the sheet's own space, spans included, so a cell
  /// merged across three columns is ringed as the one cell it is.
  Rect rectOf(TableBlock table, SheetCell cell) {
    final home = anchorOf(table, cell);
    final held = cellAt(table, home.row, home.column);
    final across = math.max(1, held?.colSpan ?? 1);
    final down = math.max(1, held?.rowSpan ?? 1);
    final left = leftOf(home.column);
    final top = topOf(home.row);
    return Rect.fromLTRB(
      left,
      top,
      leftOf(math.min(columnCount, home.column + across)),
      topOf(math.min(rowCount, home.row + down)),
    );
  }

  /// The cell that actually holds [cell], which is itself unless it has been
  /// swallowed by a merge that starts somewhere above or to its left.
  SheetCell anchorOf(TableBlock table, SheetCell cell) {
    if (cell.column < 0 || cell.column >= columnCount) return cell;
    return _covered[cell.row * columnCount + cell.column] ?? cell;
  }

  /// The column [x] falls in, in the sheet's own space.
  int columnAt(double x) => _at(lefts, x, columnCount);

  /// The row [y] falls in, in the sheet's own space.
  int rowAt(double y) => _at(tops, y, rowCount);

  /// The columns worth drawing for a viewport running from [from] to [to].
  ({int first, int last}) columnsIn(double from, double to) =>
      (first: columnAt(from), last: columnAt(to - 0.001));

  ({int first, int last}) rowsIn(double from, double to) =>
      (first: rowAt(from), last: rowAt(to - 0.001));

  /// How far the grid can be pushed on each axis before it runs out, given a
  /// viewport of [view] and the frozen panes held out of it: as much of them
  /// as there was room to hold, when that is less than the file asks for.
  Offset limitFor(Size view, {Size? frozen}) => Offset(
    math.max(
      0,
      size.width -
          (frozen?.width ?? frozenWidth) -
          (view.width - kRowHeaderWidth),
    ),
    math.max(
      0,
      size.height -
          (frozen?.height ?? frozenHeight) -
          (view.height - kGridHeaderHeight),
    ),
  );

  static int _columnCount(TableBlock table) {
    var most = table.columns.length;
    for (final row in table.rows) {
      var wide = 0;
      for (final cell in row.cells) {
        wide += math.max(1, cell.colSpan);
      }
      if (wide > most) most = wide;
    }
    return most;
  }

  /// A file that froze nothing but opened with a header row still has one, and
  /// a reader who scrolls past it loses what every column is.
  static int _frozenRows(TableBlock table) {
    if (table.frozenRows > 0) {
      return table.frozenRows.clamp(0, table.rows.length);
    }
    if (table.rows.isNotEmpty && table.rows.first.header) return 1;
    return 0;
  }

  static List<double> _running(List<double> sizes) {
    final out = <double>[0];
    var total = 0.0;
    for (final size in sizes) {
      total += size;
      out.add(total);
    }
    return out;
  }

  static int _at(List<double> edges, double value, int count) {
    if (count == 0) return 0;
    if (value <= 0) return 0;
    if (value >= edges.last) return count - 1;
    var low = 0;
    var high = count - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (value < edges[mid + 1]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}
