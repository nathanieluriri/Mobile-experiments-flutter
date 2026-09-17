import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../model/document.dart';
import '../screens/reader/bodies/sheet_geometry.dart';
import '../screens/reader/bodies/spine_table.dart'
    show SheetCell, SheetFace, cellAt, columnLetter, flattenCell, rawValueOf;
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';

/// One pane of the grid: the cells themselves, the letters, or the numbers.
///
/// They are drawn by one painter rather than four, because every one of them
/// is the same question asked at a different corner: which rows and columns
/// fall in this box, and where does each one sit once the sheet has been
/// pushed by [offset].
enum GridPane { cells, letters, numbers, corner }

/// The sheet, painted.
///
/// Only what is in the box is drawn: a workbook with forty thousand rows
/// paints the fifteen that are on screen. Everything it needs is worked out by
/// [SheetGeometry], so panning repaints and lays out nothing.
class GridPainter extends CustomPainter {
  const GridPainter({
    required this.table,
    required this.geometry,
    required this.pane,
    required this.offset,
    required this.selected,
    required this.ring,
    required this.matches,
    required this.commented,
    required this.raggedRows,
    this.face = SheetFace.front,
    this.textScale = 1,
  });

  final TableBlock table;
  final SheetGeometry geometry;
  final GridPane pane;

  /// How far the sheet has been pushed, in its own space. A frozen pane
  /// ignores one axis of it, which is the whole of what frozen means.
  final Offset offset;

  /// The cell the reader has chosen, if any.
  final SheetCell? selected;

  /// Where the ring is at this moment, in the sheet's own space, which is not
  /// the chosen cell's own rectangle while it is still travelling.
  final Rect? ring;

  /// Cells the find lit.
  final Set<SheetCell> matches;

  /// Cells carrying a discussion, which wear the corner mark.
  final Set<SheetCell> commented;

  /// Rows a CSV could not fit to its header, numbered in the damage colour.
  final Set<int> raggedRows;

  /// Which face of the sheet this is: what the file shows, or what it stores.
  final SheetFace face;

  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pane) {
      case GridPane.corner:
        _corner(canvas, size);
      case GridPane.letters:
        _letters(canvas, size);
      case GridPane.numbers:
        _numbers(canvas, size);
      case GridPane.cells:
        _cells(canvas, size);
    }
  }

  // ------------------------------------------------------------- the cells

  void _cells(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.surface,
    );
    final columns = geometry.columnsIn(offset.dx, offset.dx + size.width);
    final rows = geometry.rowsIn(offset.dy, offset.dy + size.height);
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;

    // The cells first, then the rules over them, so a fill never eats the line
    // between two columns.
    for (var r = rows.first; r <= rows.last && r < geometry.rowCount; r++) {
      for (
        var c = columns.first;
        c <= columns.last && c < geometry.columnCount;
        c++
      ) {
        _cell(canvas, r, c);
      }
    }
    for (
      var c = columns.first;
      c <= columns.last + 1 && c <= geometry.columnCount;
      c++
    ) {
      final x = geometry.leftOf(c) - offset.dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), rule);
    }
    for (var r = rows.first; r <= rows.last + 1 && r <= geometry.rowCount; r++) {
      final y = geometry.topOf(r) - offset.dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rule);
    }
    _ring(canvas, size);
  }

  void _cell(Canvas canvas, int row, int column) {
    final held = cellAt(table, row, column);
    if (held == null || held.merged) return;
    final rect = geometry
        .rectOf(table, SheetCell(row, column))
        .shift(-offset);
    final fill = held.background;
    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = Color(fill));
    }
    final found = matches.contains(SheetCell(row, column));
    if (found) {
      canvas.drawRect(rect, Paint()..color = AppColors.foundWash);
    }
    final text = flattenCell(
      face == SheetFace.front ? held.text : rawValueOf(held),
    );
    if (text.isNotEmpty) {
      _write(
        canvas,
        text,
        rect,
        held: held,
        onFill: fill != null,
        header: row < geometry.frozenRows,
      );
    }
    if (commented.contains(SheetCell(row, column))) {
      _commentMark(canvas, rect);
    }
  }

  /// One cell's own words, clipped to the cell so a long value never runs into
  /// the next column, which is how a grid keeps its columns.
  void _write(
    Canvas canvas,
    String text,
    Rect rect, {
    required DocCell held,
    required bool onFill,
    required bool header,
  }) {
    final style = AppText.cell.copyWith(
      color: onFill ? AppColors.pageInk : AppColors.ink,
      fontWeight: header || _bold(held) ? FontWeight.w600 : FontWeight.w400,
      fontFeatures: held.numeric
          ? const <ui.FontFeature>[ui.FontFeature.tabularFigures()]
          : null,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: math.max(0, rect.width - kGridCellPadX * 2));
    final free = rect.width - kGridCellPadX * 2 - painter.width;
    final x = switch (_alignOf(held)) {
      DocAlign.end => rect.left + kGridCellPadX + math.max(0, free),
      DocAlign.center => rect.left + kGridCellPadX + math.max(0, free) / 2,
      DocAlign.justify || DocAlign.start => rect.left + kGridCellPadX,
    };
    canvas
      ..save()
      ..clipRect(rect);
    painter.paint(canvas, Offset(x, rect.center.dy - painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  DocAlign _alignOf(DocCell cell) =>
      cell.align ?? (cell.numeric ? DocAlign.end : DocAlign.start);

  bool _bold(DocCell cell) {
    for (final block in cell.blocks) {
      if (block is ParagraphBlock) {
        for (final span in block.spans) {
          if (span.bold) return true;
        }
      }
    }
    return false;
  }

  /// The little corner a cell wears when somebody has said something about it.
  void _commentMark(Canvas canvas, Rect rect) {
    final path = Path()
      ..moveTo(rect.right - kGridCommentMark, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + kGridCommentMark)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.found);
  }

  /// The ring round the chosen cell, with a handle at each far corner, which
  /// is what a spreadsheet has always used to say where you are.
  void _ring(Canvas canvas, Size size) {
    final where = ring;
    if (where == null) return;
    final rect = where.shift(-offset);
    if (!rect.overlaps(Offset.zero & size)) return;
    canvas.drawRect(
      rect.deflate(kGridRingWidth / 2),
      Paint()
        ..color = AppColors.accentBright
        ..style = PaintingStyle.stroke
        ..strokeWidth = kGridRingWidth,
    );
    final knob = Paint()..color = AppColors.accentBright;
    canvas
      ..drawCircle(rect.topLeft, kGridHandle, knob)
      ..drawCircle(rect.bottomRight, kGridHandle, knob);
  }

  // ------------------------------------------------------------- the bands

  void _letters(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.surfaceHigh,
    );
    final columns = geometry.columnsIn(offset.dx, offset.dx + size.width);
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (
      var c = columns.first;
      c <= columns.last && c < geometry.columnCount;
      c++
    ) {
      final left = geometry.leftOf(c) - offset.dx;
      final rect = Rect.fromLTWH(left, 0, geometry.widthOf(c), size.height);
      final lit = selected?.column == c;
      if (lit) {
        canvas.drawRect(rect, Paint()..color = AppColors.accentMuted);
      }
      _label(canvas, columnLetter(c), rect, lit: lit);
      canvas.drawLine(
        Offset(rect.right, 0),
        Offset(rect.right, size.height),
        rule,
      );
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      rule,
    );
  }

  void _numbers(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.surfaceHigh,
    );
    final rows = geometry.rowsIn(offset.dy, offset.dy + size.height);
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var r = rows.first; r <= rows.last && r < geometry.rowCount; r++) {
      final top = geometry.topOf(r) - offset.dy;
      final rect = Rect.fromLTWH(0, top, size.width, geometry.heightOf(r));
      final lit = selected?.row == r;
      if (lit) {
        canvas.drawRect(rect, Paint()..color = AppColors.accentMuted);
      }
      _label(
        canvas,
        '${r + 1}',
        rect,
        lit: lit,
        damaged: raggedRows.contains(r),
      );
      canvas.drawLine(
        Offset(0, rect.bottom),
        Offset(size.width, rect.bottom),
        rule,
      );
    }
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      rule,
    );
  }

  void _corner(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = AppColors.surfaceHigh)
      ..drawLine(
        Offset(size.width - 0.5, 0),
        Offset(size.width - 0.5, size.height),
        Paint()
          ..color = AppColors.hairline
          ..strokeWidth = 1,
      )
      ..drawLine(
        Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5),
        Paint()
          ..color = AppColors.hairline
          ..strokeWidth = 1,
      );
  }

  void _label(
    Canvas canvas,
    String text,
    Rect rect, {
    required bool lit,
    bool damaged = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.micro.copyWith(
          color: damaged
              ? AppColors.damage
              : lit
              ? AppColors.ink
              : AppColors.inkFaint,
          fontWeight: lit ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: rect.width);
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.table != table ||
      old.geometry != geometry ||
      old.pane != pane ||
      old.offset != offset ||
      old.selected != selected ||
      old.ring != ring ||
      old.matches != matches ||
      old.commented != commented ||
      old.face != face ||
      old.textScale != textScale;
}
