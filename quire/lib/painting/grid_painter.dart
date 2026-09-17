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
    required this.lit,
    required this.ring,
    required this.matches,
    required this.commented,
    required this.raggedRows,
    this.face = SheetFace.front,
    this.textScale = 1,
    this.litRound = 0,
    this.ringStrength = 1,
  });

  final TableBlock table;
  final SheetGeometry geometry;
  final GridPane pane;

  /// How far the sheet has been pushed, in its own space. A frozen pane
  /// ignores one axis of it, which is the whole of what frozen means.
  final Offset offset;

  /// The stretch of letters and numbers lit for the chosen cell, in the
  /// sheet's own space: its left and right are the columns lit along the top,
  /// its top and bottom the rows lit down the side.
  ///
  /// It is a span rather than a cell because it travels. When the choice
  /// moves, the edge on the side it is going sets off first and the other
  /// follows, so the lit letter crawls across rather than jumping.
  final Rect? lit;

  /// How round the ends of [lit] are, which is nought at rest and more while
  /// it is stretched out between two places.
  final double litRound;

  /// Where the ring is at this moment, in the sheet's own space, which is not
  /// the chosen cell's own rectangle while it is still travelling.
  final Rect? ring;

  /// How much of the ring there is, from nought as it draws into the goo to
  /// one once it has opened out of it.
  final double ringStrength;

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
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.surface);
    final columns = geometry.columnsIn(offset.dx, offset.dx + size.width);
    final rows = geometry.rowsIn(offset.dy, offset.dy + size.height);
    final firstRow = rows.first;
    final lastRow = math.min(rows.last, geometry.rowCount - 1);
    final firstColumn = columns.first;
    final lastColumn = math.min(columns.last, geometry.columnCount - 1);
    if (lastRow < firstRow || lastColumn < firstColumn) {
      _ring(canvas, size);
      return;
    }

    // Every cell showing, a merge counted once however much of it shows and
    // wherever it starts, so a merged title half scrolled off is still drawn.
    final shown = <SheetCell>[];
    final seen = <SheetCell>{};
    for (var r = firstRow; r <= lastRow; r++) {
      for (var c = firstColumn; c <= lastColumn; c++) {
        final home = geometry.anchorOf(table, SheetCell(r, c));
        if (seen.add(home)) shown.add(home);
      }
    }

    // The grounds first, every one of them, so words running on from a cell
    // into the empty one beside it are not painted over by that one's fill.
    for (final cell in shown) {
      _ground(canvas, cell);
    }

    // Then the words, planned before the rules are drawn, since a line of
    // words running across a column takes the rule it crosses with it. A cell
    // just off to the left whose words run on into view is planned too.
    final runs = <_Run>[];
    final crossed = <int>{};
    for (final cell in shown) {
      final run = _plan(cell, crossed);
      if (run != null) runs.add(run);
    }
    for (var r = firstRow; r <= lastRow; r++) {
      for (var c = firstColumn - 1; c >= 0 && c >= firstColumn - 24; c--) {
        final home = geometry.anchorOf(table, SheetCell(r, c));
        final held = cellAt(table, home.row, home.column);
        if (held == null || _textOf(held).isEmpty) continue;
        if (seen.add(home)) {
          final run = _plan(home, crossed);
          if (run != null) runs.add(run);
        }
        break;
      }
    }

    _rules(canvas, size, firstRow, lastRow, firstColumn, lastColumn, crossed);

    for (final run in runs) {
      canvas
        ..save()
        ..clipRect(run.clip);
      run.painter.paint(canvas, run.at);
      canvas.restore();
      run.painter.dispose();
    }
    for (final cell in shown) {
      final held = cellAt(table, cell.row, cell.column);
      if (held == null) continue;
      if (held.comment != null || commented.contains(cell)) {
        _commentMark(canvas, geometry.rectOf(table, cell).shift(-offset));
      }
    }
    _ring(canvas, size);
  }

  /// A cell's fill and, when a find matched it, the wash over the fill.
  void _ground(Canvas canvas, SheetCell cell) {
    final held = cellAt(table, cell.row, cell.column);
    if (held == null || held.merged) return;
    final rect = geometry.rectOf(table, cell).shift(-offset);
    final fill = held.background;
    if (fill != null) {
      canvas.drawRect(rect, Paint()..color = Color(fill));
    }
    if (matches.contains(cell)) {
      canvas.drawRect(rect, Paint()..color = AppColors.foundWash);
    }
  }

  /// The rules between cells: none inside a merge, and none under a line of
  /// words that runs across from one cell into the next, which is how a
  /// spreadsheet shows that the words belong to the cell they started in.
  void _rules(
    Canvas canvas,
    Size size,
    int firstRow,
    int lastRow,
    int firstColumn,
    int lastColumn,
    Set<int> crossed,
  ) {
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    for (var c = firstColumn; c <= lastColumn + 1; c++) {
      final x = geometry.leftOf(c) - offset.dx;
      for (var r = firstRow; r <= lastRow; r++) {
        if (c > 0 && c < geometry.columnCount) {
          final left = geometry.anchorOf(table, SheetCell(r, c - 1));
          final right = geometry.anchorOf(table, SheetCell(r, c));
          if (left == right || crossed.contains(_key(r, c))) continue;
        }
        canvas.drawLine(
          Offset(x, geometry.topOf(r) - offset.dy),
          Offset(x, geometry.topOf(r + 1) - offset.dy),
          rule,
        );
      }
    }
    for (var r = firstRow; r <= lastRow + 1; r++) {
      final y = geometry.topOf(r) - offset.dy;
      for (var c = firstColumn; c <= lastColumn; c++) {
        if (r > 0 && r < geometry.rowCount) {
          final above = geometry.anchorOf(table, SheetCell(r - 1, c));
          final below = geometry.anchorOf(table, SheetCell(r, c));
          if (above == below) continue;
        }
        canvas.drawLine(
          Offset(geometry.leftOf(c) - offset.dx, y),
          Offset(geometry.leftOf(c + 1) - offset.dx, y),
          rule,
        );
      }
    }
  }

  int _key(int row, int column) => row * (geometry.columnCount + 1) + column;

  String _textOf(DocCell held) =>
      flattenCell(face == SheetFace.front ? held.text : rawValueOf(held));

  /// True when [row], [column] holds nothing a line of words could not run
  /// on across: no words of its own, and no part of a merge.
  bool _open(int row, int column) {
    if (column < 0 || column >= geometry.columnCount) return false;
    final held = cellAt(table, row, column);
    if (held == null) return true;
    if (held.merged || held.colSpan > 1 || held.rowSpan > 1) return false;
    return _textOf(held).isEmpty;
  }

  /// Where a cell's words go and how far they may run.
  ///
  /// Words that fit sit in their own cell. Words that do not, in a cell of
  /// words rather than a number, run on across the empty cells beside them
  /// in the direction they are set, the way a spreadsheet lets a title in A1
  /// be read in full, and stop at the first cell that has something in it.
  /// A number never runs on, because a number cut short and a number run
  /// into its neighbour are both wrong, and it shows from its start. The
  /// rules the words cross are added to [crossed].
  _Run? _plan(SheetCell cell, Set<int> crossed) {
    final held = cellAt(table, cell.row, cell.column);
    if (held == null || held.merged) return null;
    final text = _textOf(held);
    if (text.isEmpty) return null;
    final rect = geometry.rectOf(table, cell).shift(-offset);
    if (rect.width <= 0 || rect.height <= 0) return null;
    final first = _firstSpan(held);
    final bold =
        _bold(held) || (table.frozenRows == 0 && table.rows[cell.row].header);
    final room = rect.width - kGridCellPadX * 2;
    // Words the file wraps take as many lines as the cell's width makes, and
    // are cut at the cell's edges rather than running on.
    final wraps = held.wrap && !held.numeric;
    final painter = TextPainter(
      text: TextSpan(
        text: wraps
            ? (face == SheetFace.front ? held.text : rawValueOf(held)).trim()
            : text,
        style: AppText.cell.copyWith(
          color: _inkFor(held, first?.color),
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          fontStyle: first?.italic ?? false ? FontStyle.italic : null,
          fontFeatures: held.numeric
              ? const <ui.FontFeature>[ui.FontFeature.tabularFigures()]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: wraps ? null : 1,
      textScaler: TextScaler.linear(textScale),
    )..layout(maxWidth: wraps ? math.max(0, room) : double.infinity);
    final free = room - painter.width;
    final align = _alignOf(held);
    var clip = rect;
    final spans = held.colSpan > 1 || held.rowSpan > 1;
    if (free < 0 && !held.numeric && !spans && !wraps) {
      var left = rect.left;
      var right = rect.right;
      var need = -free;
      final rightward = align != DocAlign.end;
      final leftward = align == DocAlign.end || align == DocAlign.center;
      if (align == DocAlign.center) need /= 2;
      if (rightward) {
        var c = cell.column + 1;
        var got = 0.0;
        while (got < need && _open(cell.row, c)) {
          crossed.add(_key(cell.row, c));
          got += geometry.widthOf(c);
          right += geometry.widthOf(c);
          c++;
        }
      }
      if (leftward) {
        var c = cell.column - 1;
        var got = 0.0;
        while (got < need && _open(cell.row, c)) {
          crossed.add(_key(cell.row, c + 1));
          got += geometry.widthOf(c);
          left -= geometry.widthOf(c);
          c--;
        }
      }
      clip = Rect.fromLTRB(left, rect.top, right, rect.bottom);
    }
    final x = switch (align) {
      DocAlign.end when free >= 0 || !held.numeric =>
        rect.right - kGridCellPadX - painter.width,
      DocAlign.center => rect.center.dx - painter.width / 2,
      _ => rect.left + kGridCellPadX,
    };
    // Up and down as the file sets it. Words taller than their cell start at
    // its top, since the start of them is what is read first.
    final tall = painter.height > rect.height - kGridCellPadY * 2;
    final y = tall
        ? rect.top + kGridCellPadY
        : switch (held.verticalAlign) {
            DocVerticalAlign.top => rect.top + kGridCellPadY,
            DocVerticalAlign.bottom =>
              rect.bottom - kGridCellPadY - painter.height,
            _ => rect.center.dy - painter.height / 2,
          };
    return _Run(painter: painter, at: Offset(x, y), clip: clip);
  }

  DocSpan? _firstSpan(DocCell cell) {
    for (final block in cell.blocks) {
      if (block is ParagraphBlock && block.spans.isNotEmpty) {
        return block.spans.first;
      }
    }
    return null;
  }

  /// The colour a cell's words are set in.
  ///
  /// On a fill, the file's own colour when it can be read against that fill,
  /// and otherwise dark or light ink by how light the fill is, so white words
  /// on a navy header stay white and nothing is ever set dark on dark. On the
  /// sheet's own dark ground, a colour the file chose to mean something, a
  /// red flag or a green total, is kept and lifted until it can be read,
  /// while black and the greys are the sheet's own ink: they were chosen for
  /// white paper, and on this sheet they would be invisible.
  Color _inkFor(DocCell held, int? stated) {
    final fill = held.background;
    if (fill != null) {
      final ground = Color(fill);
      if (stated != null && _contrast(Color(stated), ground) >= 3) {
        return Color(stated);
      }
      return ground.computeLuminance() > 0.3
          ? AppColors.pageInk
          : AppColors.ink;
    }
    if (stated == null) return AppColors.ink;
    final colour = Color(stated);
    final most = math.max(colour.r, math.max(colour.g, colour.b));
    final least = math.min(colour.r, math.min(colour.g, colour.b));
    if (most - least < 0.2) return AppColors.ink;
    var lifted = HSLColor.fromColor(colour);
    while (_contrast(lifted.toColor(), AppColors.surface) < 4.5 &&
        lifted.lightness < 0.9) {
      lifted = lifted.withLightness(math.min(0.9, lifted.lightness + 0.05));
    }
    return lifted.toColor();
  }

  static double _contrast(Color a, Color b) {
    final one = a.computeLuminance();
    final two = b.computeLuminance();
    return (math.max(one, two) + 0.05) / (math.min(one, two) + 0.05);
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
    if (where == null || ringStrength <= 0) return;
    final rect = where.shift(-offset);
    if (!rect.overlaps(Offset.zero & size)) return;
    final colour = AppColors.accentBright.withValues(
      alpha: AppColors.accentBright.a * ringStrength.clamp(0.0, 1.0),
    );
    canvas.drawRect(
      rect.deflate(kGridRingWidth / 2),
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = kGridRingWidth,
    );
    // The handles go with the ring, shrinking into the goo as it draws in.
    final knob = Paint()..color = colour;
    final handle = kGridHandle * ringStrength.clamp(0.0, 1.0);
    canvas
      ..drawCircle(rect.topLeft, handle, knob)
      ..drawCircle(rect.bottomRight, handle, knob);
  }

  // ------------------------------------------------------------- the bands

  void _letters(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.surfaceHigh);
    final columns = geometry.columnsIn(offset.dx, offset.dx + size.width);
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final span = lit;
    if (span != null) {
      _litFill(
        canvas,
        Rect.fromLTRB(
          span.left - offset.dx,
          0,
          span.right - offset.dx,
          size.height,
        ),
      );
    }
    for (
      var c = columns.first;
      c <= columns.last && c < geometry.columnCount;
      c++
    ) {
      final left = geometry.leftOf(c) - offset.dx;
      final rect = Rect.fromLTWH(left, 0, geometry.widthOf(c), size.height);
      if (rect.width <= 0) continue;
      // A column wider than what shows of it has its letter in the part that
      // shows, so the letter is never off the side of the screen.
      final shown = Rect.fromLTRB(
        math.max(rect.left, 0),
        rect.top,
        math.min(rect.right, size.width),
        rect.bottom,
      );
      _label(
        canvas,
        columnLetter(c),
        shown.width > 0 ? shown : rect,
        lit: _cover(span?.left, span?.right, rect.left + offset.dx, rect.width),
      );
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
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.surfaceHigh);
    final rows = geometry.rowsIn(offset.dy, offset.dy + size.height);
    final rule = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final span = lit;
    if (span != null) {
      _litFill(
        canvas,
        Rect.fromLTRB(
          0,
          span.top - offset.dy,
          size.width,
          span.bottom - offset.dy,
        ),
      );
    }
    for (var r = rows.first; r <= rows.last && r < geometry.rowCount; r++) {
      final top = geometry.topOf(r) - offset.dy;
      final rect = Rect.fromLTWH(0, top, size.width, geometry.heightOf(r));
      if (rect.height <= 0) continue;
      _label(
        canvas,
        '${r + 1}',
        rect,
        lit: _cover(span?.top, span?.bottom, rect.top + offset.dy, rect.height),
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

  /// The lit stretch of a band, rounded at its ends while it travels.
  void _litFill(Canvas canvas, Rect band) {
    if (band.width <= 0 || band.height <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        band,
        Radius.circular(math.min(litRound, band.shortestSide / 2)),
      ),
      Paint()..color = AppColors.accentMuted,
    );
  }

  /// How much of a column or row, starting at [start] and [length] long, lies
  /// under the lit stretch from [from] to [to].
  static double _cover(double? from, double? to, double start, double length) {
    if (from == null || to == null || length <= 0) return 0;
    final under = math.min(to, start + length) - math.max(from, start);
    return (under / length).clamp(0.0, 1.0);
  }

  /// A letter or a number, darkening as the lit stretch comes over it.
  void _label(
    Canvas canvas,
    String text,
    Rect rect, {
    required double lit,
    bool damaged = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppText.micro.copyWith(
          color: damaged
              ? AppColors.damage
              : Color.lerp(AppColors.inkFaint, AppColors.ink, lit),
          fontWeight: lit >= 0.5 ? FontWeight.w600 : FontWeight.w500,
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
      old.lit != lit ||
      old.litRound != litRound ||
      old.ring != ring ||
      old.ringStrength != ringStrength ||
      old.matches != matches ||
      old.commented != commented ||
      old.face != face ||
      old.textScale != textScale;
}

/// A cell's words, laid out, with where they go and how far they may show.
class _Run {
  const _Run({required this.painter, required this.at, required this.clip});

  final TextPainter painter;
  final Offset at;
  final Rect clip;
}
