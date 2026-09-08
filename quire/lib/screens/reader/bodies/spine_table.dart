import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../painting/spine_glyph_painter.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';

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
List<double> spineWidths(int columns, {required int open}) {
  final widths = columnWidths(columns);
  return <double>[
    for (var c = 0; c < columns; c++) c == open ? widths.open : widths.spine,
  ];
}

/// How far the cells are shifted left so the open column meets the row header.
///
/// It is clamped to what there is to scroll, so a sheet that already fits the
/// phone never slides: the spine table's whole point is that the common case
/// needs no scrolling at all.
double openOffset(List<double> widths, int open) {
  var left = 0.0;
  for (var c = 0; c < open && c < widths.length; c++) {
    left += widths[c];
  }
  var content = 0.0;
  for (final width in widths) {
    content += width;
  }
  const viewport = kSheetWidth - kRowHeaderWidth;
  return left.clamp(0.0, math.max(0.0, content - viewport));
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

/// The spreadsheet, laid out as one open column beside a strip chart.
///
/// Everything about it is a pure function of the table, the open column and
/// the widths handed in, so the animating parts live above it and this stays
/// something a golden can be trusted about.
class SpineTable extends StatelessWidget {
  const SpineTable({
    super.key,
    required this.table,
    required this.widths,
    required this.scales,
    required this.offset,
    required this.scroll,
    this.face = SheetFace.front,
    this.selected,
    this.matches = const <SheetCell>{},
    this.raggedRows = const <int>{},
    this.onCellTap,
    this.onSpineTap,
  });

  /// The grid this sheet holds.
  final TableBlock table;

  /// Each column's width this frame, mid animation included.
  final List<double> widths;

  /// The largest magnitude in each column, from [columnScales].
  final List<double> scales;

  /// How far the cells are shifted left this frame.
  final double offset;

  /// The body list's scroll controller, owned above so a sheet keeps its place
  /// when the reader turns it over or steps away to another sheet.
  final ScrollController scroll;

  final SheetFace face;

  /// The ringed cell, always in the open column.
  final SheetCell? selected;

  /// Cells the current query found.
  final Set<SheetCell> matches;

  /// Rows whose field count did not match the header's, which a CSV numbers in
  /// [AppColors.damage] rather than quietly padding out.
  final Set<int> raggedRows;

  final void Function(SheetCell cell)? onCellTap;
  final void Function(int column)? onSpineTap;

  /// How many rows at the top of the file are its heading, the last of which
  /// supplies the header band's labels.
  int get headerRows {
    if (table.frozenRows > 0) return table.frozenRows;
    if (table.rows.isNotEmpty && table.rows.first.header) return 1;
    return 0;
  }

  /// The row whose cells label the columns, or null when the file has none.
  int? get labelRow => headerRows == 0 ? null : headerRows - 1;

  /// The first row of data.
  int get bodyFrom => headerRows;

  /// How many columns the sheet has, which is however many widths the caller
  /// worked out. Taking it from [widths] rather than rewalking the rows keeps
  /// the two from ever disagreeing about the shape of the grid.
  int get columnCount => widths.length;

  @override
  Widget build(BuildContext context) {
    final pinned = <int>[for (var r = 0; r < headerRows - 1; r++) r];
    return ColoredBox(
      color: face == SheetFace.front ? AppColors.leaf : AppColors.leafBack,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          for (final row in pinned) _row(row, pinned: true),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: EdgeInsets.zero,
              itemExtent: kTableRowHeight,
              itemCount: math.max(0, table.rows.length - bodyFrom),
              itemBuilder: (context, index) => _row(bodyFrom + index),
            ),
          ),
        ],
      ),
    );
  }

  /// The band of column letters and header labels, which never scrolls away.
  Widget _header() {
    return SizedBox(
      height: kTableHeaderHeight,
      child: Container(
        decoration: const BoxDecoration(color: AppColors.panel),
        foregroundDecoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.rule)),
        ),
        child: Row(
          children: [
            const _RowHeaderCell(),
            Expanded(
              child: _Cells(
                widths: widths,
                offset: offset,
                height: kTableHeaderHeight,
                builder: _headerCell,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(int column, double openness) {
    final label = labelRow == null
        ? ''
        : flattenCell(cellAt(table, labelRow!, column)?.text ?? '');
    final letter = Text(
      columnLetter(column),
      style: AppText.micro.copyWith(color: AppColors.inkFaint),
      maxLines: 1,
    );
    final bounds = columnWidths(columnCount);
    return _Crossfade(
      openness: openness,
      openWidth: bounds.open,
      spineWidth: bounds.spine,
      open: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kCellPaddingX),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            letter,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: AppText.cellHeader.copyWith(color: AppColors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
      folded: ClipRect(
        child: Center(child: RotatedBox(quarterTurns: 3, child: letter)),
      ),
    );
  }

  /// One row of the grid: its number, its cells, its stripe and its hairline.
  Widget _row(int row, {bool pinned = false}) {
    final ordinal = row - bodyFrom;
    final leader = pinned || (ordinal + 1) % kLeaderEvery == 0;
    final striped = !pinned && ordinal.isOdd;
    return SizedBox(
      height: kTableRowHeight,
      child: Container(
        decoration: BoxDecoration(
          color: face == SheetFace.back
              ? AppColors.leafBack
              : (striped ? AppColors.zebra : AppColors.leaf),
        ),
        foregroundDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: leader ? AppColors.rule : AppColors.ruleFaint,
            ),
          ),
        ),
        child: Row(
          children: [
            _RowHeaderCell(number: row + 1, ragged: raggedRows.contains(row)),
            Expanded(
              child: _Cells(
                widths: widths,
                offset: offset,
                height: kTableRowHeight,
                builder: (column, openness) =>
                    _bodyCell(row, column, openness),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodyCell(int row, int column, double openness) {
    final cell = cellAt(table, row, column);
    final ringed = selected == SheetCell(row, column);
    final numeric = cell?.numeric ?? false;
    final text = cell == null
        ? ''
        : (face == SheetFace.front
              ? flattenCell(cell.text)
              : rawValueOf(cell));
    final open = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCellTap == null
          ? null
          : () => onCellTap!(SheetCell(row, column)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ringed ? AppColors.threadWash : null,
          border: ringed
              ? Border.all(color: AppColors.thread, width: 2)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kCellPaddingX),
          child: Align(
            alignment: numeric
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Text(
              text,
              style: face == SheetFace.front
                  ? AppText.cell.copyWith(color: AppColors.ink)
                  : AppText.code.copyWith(color: AppColors.inkSoft),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              textAlign: numeric ? TextAlign.right : TextAlign.left,
            ),
          ),
        ),
      ),
    );
    final folded = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSpineTap == null ? null : () => onSpineTap!(column),
      child: CustomPaint(
        painter: SpineGlyphPainter(_markFor(row, column)),
        size: Size.infinite,
      ),
    );
    final bounds = columnWidths(columnCount);
    return _Crossfade(
      openness: openness,
      openWidth: bounds.open,
      spineWidth: bounds.spine,
      open: open,
      folded: folded,
    );
  }

  /// One cell's mark, scaled against the largest number in its own column.
  SpineValue _markFor(int row, int column) {
    final cell = cellAt(table, row, column);
    final found = matches.contains(SheetCell(row, column));
    if (cell == null || cell.merged || cell.text.trim().isEmpty) {
      return SpineValue(SpineMark.none, found: found);
    }
    final raw = cell.raw;
    final largest = column < scales.length ? scales[column] : 0.0;
    if (raw is num && largest > 0) {
      return SpineValue(
        SpineMark.bar,
        extent: raw.abs().toDouble() / largest,
        found: found,
      );
    }
    return SpineValue(SpineMark.dot, found: found);
  }
}

/// The frozen forty point column of row numbers down the left of the grid.
class _RowHeaderCell extends StatelessWidget {
  const _RowHeaderCell({this.number, this.ragged = false});

  final int? number;
  final bool ragged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kRowHeaderWidth,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: kCellPaddingX),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.rule)),
      ),
      child: number == null
          ? null
          : Text(
              '$number',
              style: AppText.folioSmall.copyWith(
                color: ragged ? AppColors.damage : AppColors.inkFaint,
              ),
              maxLines: 1,
            ),
    );
  }
}

/// The cells of one row, laid out at their widths and shifted by the scroll.
///
/// The shift is a translation rather than a [Scrollable] because the row
/// header has to stay put: two scroll views synchronised on one axis is the
/// two axis grid the spine table exists to avoid.
class _Cells extends StatelessWidget {
  const _Cells({
    required this.widths,
    required this.offset,
    required this.height,
    required this.builder,
  });

  final List<double> widths;
  final double offset;
  final double height;
  final Widget Function(int column, double openness) builder;

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    for (final width in widths) {
      total += width;
    }
    final bounds = columnWidths(widths.length);
    final span = bounds.open - bounds.spine;
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: double.infinity,
        child: Transform.translate(
          offset: Offset(-offset, 0),
          child: SizedBox(
            width: total,
            height: height,
            child: Row(
              children: [
                for (var c = 0; c < widths.length; c++)
                  SizedBox(
                    width: widths[c],
                    child: builder(
                      c,
                      span <= 0
                          ? 1.0
                          : ((widths[c] - bounds.spine) / span).clamp(0.0, 1.0),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A column part way between a spine and the open column.
///
/// Each face is laid out at its own resting width and clipped to whatever the
/// column is this frame, so the cell's text is revealed rather than reflowed:
/// a paragraph that rewraps twelve times over 240 ms is the churn the fixed
/// widths of section 6.4 exist to avoid.
class _Crossfade extends StatelessWidget {
  const _Crossfade({
    required this.openness,
    required this.openWidth,
    required this.spineWidth,
    required this.open,
    required this.folded,
  });

  final double openness;
  final double openWidth;
  final double spineWidth;
  final Widget open;
  final Widget folded;

  @override
  Widget build(BuildContext context) {
    if (openness >= 1) return _at(openWidth, open);
    if (openness <= 0) return _at(spineWidth, folded);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(opacity: 1 - openness, child: _at(spineWidth, folded)),
        Opacity(opacity: openness, child: _at(openWidth, open)),
      ],
    );
  }

  /// One face at [width], however wide its column happens to be right now.
  static Widget _at(double width, Widget child) => ClipRect(
    child: OverflowBox(
      alignment: Alignment.centerLeft,
      minWidth: width,
      maxWidth: width,
      child: child,
    ),
  );
}
