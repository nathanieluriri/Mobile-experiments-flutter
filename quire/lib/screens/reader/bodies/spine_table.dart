

import '../../../model/document.dart';
import '../../../painting/spine_glyph_painter.dart';
import '../../../theme/metrics.dart';

/// One cell's address inside a sheet, as the file numbers it.
///
/// Rows and columns are the model's own indices, so a hit from the search and
/// a tap from a finger name the same cell without either having to know how
/// the table happens to be laid out at that moment.
class SheetCell {
  const SheetCell(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is SheetCell && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => 'SheetCell($row, $column)';
}

/// Which face of the sheet a table is drawn on.
enum SheetFace {
  /// The formatted cells, as the file wants them read.
  front,

  /// The stored values and the formulas behind them.
  back,
}

/// The spreadsheet letter of column [index]: A, B, ... Z, AA, AB.
String columnLetter(int index) {
  var n = index;
  final letters = <int>[];
  while (true) {
    letters.add(0x41 + n % 26);
    n = n ~/ 26 - 1;
    if (n < 0) break;
  }
  return String.fromCharCodes(letters.reversed);
}

/// What the cell bar prints: `Runs!G3`, from the model's own indices.
String cellReference(String sheetName, int column, int row) =>
    '$sheetName!${columnLetter(column)}${row + 1}';

final RegExp _whitespace = RegExp(r'\s+');

/// One line of text out of a cell that may hold several.
///
/// A CSV field is allowed to carry a newline, and a grid row that grew to two
/// lines because one cell did would break the one thing a table promises: that
/// every row is the same height and the eye can travel across it.
String flattenCell(String text) {
  if (text.isEmpty) return text;
  return text.replaceAll(_whitespace, ' ').trim();
}

/// The width of every column of a [columns] wide sheet, with [open] opened.
///
/// The reader draws its sheets on a grid now. This is what the desk's own
/// thumbnail is still laid out on, where a card is too small for a grid and
/// what it wants is the shape of the sheet rather than its cells.
List<double> spineWidths(int columns, {required int open}) {
  final widths = columnWidths(columns);
  return <double>[
    for (var c = 0; c < columns; c++) c == open ? widths.open : widths.spine,
  ];
}

/// Reduces one column of [table], from row [from] down, to its marks.
///
/// The scale is taken over the column itself rather than over the whole sheet,
/// because a spine is a chart of one measure: a quantity in the thousands
/// beside a price in pence would flatten the price to nothing.
List<SpineValue> spineValuesFor(
  TableBlock table,
  int column, {
  int from = 0,
  Set<SheetCell> matches = const <SheetCell>{},
}) {
  var largest = 0.0;
  for (var r = from; r < table.rows.length; r++) {
    final raw = cellAt(table, r, column)?.raw;
    if (raw is num) {
      final size = raw.abs().toDouble();
      if (size > largest) largest = size;
    }
  }
  final values = <SpineValue>[];
  for (var r = from; r < table.rows.length; r++) {
    final cell = cellAt(table, r, column);
    final found = matches.contains(SheetCell(r, column));
    if (cell == null || cell.merged || cell.text.trim().isEmpty) {
      values.add(SpineValue(SpineMark.none, found: found));
      continue;
    }
    final raw = cell.raw;
    if (raw is num && largest > 0) {
      values.add(
        SpineValue(
          SpineMark.bar,
          extent: raw.abs().toDouble() / largest,
          found: found,
        ),
      );
      continue;
    }
    values.add(SpineValue(SpineMark.dot, found: found));
  }
  return values;
}

/// The largest magnitude in each column, from row [from] down.
///
/// It is computed once per sheet rather than per cell, because a spine's bar
/// is a fraction of its own column and asking each of six hundred cells to
/// rescan its column would be a quadratic walk on every frame.
List<double> columnScales(TableBlock table, {int from = 0}) {
  var columns = table.columns.length;
  for (final row in table.rows) {
    if (row.cells.length > columns) columns = row.cells.length;
  }
  final scales = List<double>.filled(columns, 0);
  for (var r = from; r < table.rows.length; r++) {
    for (var c = 0; c < columns; c++) {
      final raw = cellAt(table, r, c)?.raw;
      if (raw is num && raw.abs() > scales[c]) scales[c] = raw.abs().toDouble();
    }
  }
  return scales;
}

/// The cell at [row] and [column], or null where the grid is ragged.
DocCell? cellAt(TableBlock table, int row, int column) {
  if (row < 0 || row >= table.rows.length) return null;
  final cells = table.rows[row].cells;
  if (column < 0 || column >= cells.length) return null;
  return cells[column];
}

/// What the back of a sheet prints for a stored value.
///
/// It is deliberately not the number format engine's answer: the front already
/// shows that. The back shows what is actually in the file, which is how a
/// reader finds out that a column of dates is really a column of numbers.
String rawValueOf(DocCell cell) {
  final formula = cell.formula;
  if (formula != null && formula.isNotEmpty) return '=$formula';
  final raw = cell.raw;
  switch (raw) {
    case null:
      return '';
    case final bool value:
      return value ? 'TRUE' : 'FALSE';
    case final DateTime value:
      return '${value.year.toString().padLeft(4, '0')}'
          '-${value.month.toString().padLeft(2, '0')}'
          '-${value.day.toString().padLeft(2, '0')}';
    case final num value:
      final text = value.toString();
      return text.endsWith('.0')
          ? text.substring(0, text.length - 2)
          : text;
    default:
      return flattenCell(raw.toString());
  }
}
