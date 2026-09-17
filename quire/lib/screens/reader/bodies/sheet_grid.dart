import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../painting/grid_painter.dart';
import '../../../theme/feedback.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';
import 'sheet_geometry.dart';
import 'spine_table.dart' show SheetCell, SheetFace;

/// A spreadsheet read as a spreadsheet: letters across the top, numbers down
/// the side, and the grid itself pushed under both with one finger.
///
/// The bands are not decoration. A column of dates means nothing without the
/// name at the top of it, and a row means nothing without its number, so both
/// are held while everything else moves. Whatever the file itself froze is
/// held as well, in the same way and for the same reason.
///
/// Nothing here scrolls in Flutter's sense. The sheet is painted at an offset
/// and the offset is what moves, which is what lets one finger take the grid
/// diagonally and what keeps four panes of it in step without a single
/// scroll notification passing between them.
class SheetGrid extends StatefulWidget {
  const SheetGrid({
    super.key,
    required this.table,
    required this.selected,
    required this.onSelect,
    this.matches = const <SheetCell>{},
    this.commented = const <SheetCell>{},
    this.raggedRows = const <int>{},
    this.reveal,
    this.locked = false,
    this.face = SheetFace.front,
    this.textScale = 1,
    this.onPanned,
    this.startAt = Offset.zero,
  });

  final TableBlock table;

  /// The cell the reader has chosen, which the ring travels to.
  final SheetCell? selected;
  final ValueChanged<SheetCell> onSelect;

  final Set<SheetCell> matches;
  final Set<SheetCell> commented;
  final Set<int> raggedRows;

  /// A cell the grid should bring into view, such as the one a find landed on.
  final SheetCell? reveal;

  /// True while the reading is pinned, when the grid holds still like the
  /// pages do.
  final bool locked;

  /// Which face of the sheet is showing: the values as the file formats them,
  /// or the values as it stores them.
  final SheetFace face;

  final double textScale;

  /// Where the grid has been pushed to, which row is at the top of it, and
  /// whether a finger did it.
  ///
  /// A push by hand is the reader moving through the document. A push the
  /// grid made itself, to bring a cell into view, is not, and treating the
  /// two alike would mean showing somebody a cell and then throwing away the
  /// choice that asked for it.
  final void Function(Offset pan, int topRow, bool byHand)? onPanned;
  final Offset startAt;

  @override
  State<SheetGrid> createState() => SheetGridState();
}

class SheetGridState extends State<SheetGrid> with TickerProviderStateMixin {
  late SheetGeometry _geometry = SheetGeometry.of(widget.table);

  /// How far the sheet has been pushed, in its own space.
  Offset _pan = Offset.zero;

  /// The room the scrolling part of the grid has, which the pan is held
  /// inside. It is nought until the first layout.
  Size _view = Size.zero;

  late final AnimationController _glideX;
  late final AnimationController _glideY;

  /// The ring on its way from one cell to the next.
  late final AnimationController _ringMove;
  late final SpringCurve _ringCurve;
  Rect? _ringFrom;
  Rect? _ringTo;

  @override
  void initState() {
    super.initState();
    _pan = widget.startAt;
    _glideX = AnimationController.unbounded(vsync: this)
      ..addListener(() => _pushTo(Offset(_glideX.value, _pan.dy)));
    _glideY = AnimationController.unbounded(vsync: this)
      ..addListener(() => _pushTo(Offset(_pan.dx, _glideY.value)));
    _ringMove = AnimationController(vsync: this, duration: kGridRingMove)
      ..addListener(_repaint);
    _ringCurve = SpringCurve(AppSprings.shelfLayout, duration: kGridRingMove);
    _ringTo = _rectOf(widget.selected);
  }

  @override
  void didUpdateWidget(SheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) {
      _geometry = SheetGeometry.of(widget.table);
      _pan = Offset.zero;
      _ringFrom = null;
      _ringTo = _rectOf(widget.selected);
    }
    if (oldWidget.selected != widget.selected) _moveRing();
    final reveal = widget.reveal;
    if (reveal != null && reveal != oldWidget.reveal) {
      // After this frame rather than during it: bringing a cell into view
      // moves the reader's place in the document, and the document cannot be
      // told it has moved while the screen showing it is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bring(reveal);
      });
    }
  }

  @override
  void dispose() {
    _glideX.dispose();
    _glideY.dispose();
    _ringMove.dispose();
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Rect? _rectOf(SheetCell? cell) =>
      cell == null ? null : _geometry.rectOf(widget.table, cell);

  /// The ring does not jump between cells. It travels, and it swells a little
  /// on the way, because everything in this app that moves is made of the same
  /// stuff.
  void _moveRing() {
    final to = _rectOf(widget.selected);
    if (to == null) {
      setState(() {
        _ringFrom = null;
        _ringTo = null;
      });
      return;
    }
    setState(() {
      _ringFrom = _ringNow() ?? to;
      _ringTo = to;
    });
    _ringMove.forward(from: 0);
  }

  /// Where the ring is at this moment.
  Rect? _ringNow() {
    final to = _ringTo;
    if (to == null) return null;
    final from = _ringFrom;
    if (from == null || _ringMove.isCompleted) return to;
    final t = _ringCurve.transform(_ringMove.value);
    final rect = Rect.lerp(from, to, t)!;
    // Fattest half way across, the way a drop is while it is still travelling.
    final swell = kGridRingSwell * math.sin(math.pi * t.clamp(0.0, 1.0));
    return rect.inflate(swell);
  }

  // -------------------------------------------------------------- the pan

  Offset get _limit => _geometry.limitFor(
    Size(_view.width + kRowHeaderWidth, _view.height + kGridHeaderHeight),
  );

  void _pushTo(Offset next, {bool byHand = true}) {
    final limit = _limit;
    final held = Offset(
      next.dx.clamp(0.0, limit.dx),
      next.dy.clamp(0.0, limit.dy),
    );
    if (held == _pan) return;
    setState(() => _pan = held);
    widget.onPanned?.call(
      held,
      _geometry.rowAt(held.dy + _geometry.frozenHeight),
      byHand,
    );
  }

  void _drag(DragUpdateDetails details) {
    if (widget.locked) return;
    _stopGliding();
    _pushTo(_pan - details.delta);
  }

  void _fling(DragEndDetails details) {
    if (widget.locked) return;
    final velocity = details.velocity.pixelsPerSecond;
    final limit = _limit;
    if (velocity.dx.abs() > kGridFlingFrom && limit.dx > 0) {
      _glideX.animateWith(
        FrictionSimulation(kGridFriction, _pan.dx, -velocity.dx),
      );
    }
    if (velocity.dy.abs() > kGridFlingFrom && limit.dy > 0) {
      _glideY.animateWith(
        FrictionSimulation(kGridFriction, _pan.dy, -velocity.dy),
      );
    }
  }

  void _stopGliding() {
    _glideX.stop();
    _glideY.stop();
  }

  /// Takes the grid to [cell], by the shortest push that puts it on screen.
  ///
  /// Nothing moves when the cell is already in view: a find that jumped the
  /// grid about for a match you were already looking at would be a find that
  /// loses your place to tell you where it is.
  void _bring(SheetCell cell) {
    final rect = _rectOf(cell);
    if (rect == null || _view == Size.zero) return;
    final frozen = Offset(_geometry.frozenWidth, _geometry.frozenHeight);
    var x = _pan.dx;
    var y = _pan.dy;
    final left = rect.left - frozen.dx;
    final top = rect.top - frozen.dy;
    if (left < x) x = left;
    if (rect.right - frozen.dx > x + _view.width) {
      x = rect.right - frozen.dx - _view.width;
    }
    if (top < y) y = top;
    if (rect.bottom - frozen.dy > y + _view.height) {
      y = rect.bottom - frozen.dy - _view.height;
    }
    _stopGliding();
    _pushTo(Offset(x, y), byHand: false);
  }

  /// Which cell the finger landed on, in whichever pane it landed in.
  void _tap(Offset local) {
    final frozenW = _geometry.frozenWidth;
    final frozenH = _geometry.frozenHeight;
    final inGrid = Offset(
      local.dx - kRowHeaderWidth,
      local.dy - kGridHeaderHeight,
    );
    if (inGrid.dx < 0 || inGrid.dy < 0) return;
    final x = inGrid.dx <= frozenW ? inGrid.dx : inGrid.dx + _pan.dx;
    final y = inGrid.dy <= frozenH ? inGrid.dy : inGrid.dy + _pan.dy;
    final cell = SheetCell(_geometry.rowAt(y), _geometry.columnAt(x));
    Feel.tap.ring();
    widget.onSelect(_geometry.anchorOf(widget.table, cell));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final frozenW = math.min(
          _geometry.frozenWidth,
          math.max(0.0, width - kRowHeaderWidth - kGridColumnMin),
        );
        final frozenH = math.min(
          _geometry.frozenHeight,
          math.max(0.0, height - kGridHeaderHeight - kGridRowMin),
        );
        final view = Size(
          math.max(0, width - kRowHeaderWidth - frozenW),
          math.max(0, height - kGridHeaderHeight - frozenH),
        );
        if (view != _view) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _view = view);
          });
        }
        final ring = _ringNow();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: _drag,
          onPanEnd: _fling,
          onTapUp: (details) => _tap(details.localPosition),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: kGridHeaderHeight,
                child: Row(
                  children: <Widget>[
                    _paint(
                      GridPane.corner,
                      Offset.zero,
                      ring,
                      width: kRowHeaderWidth,
                    ),
                    if (frozenW > 0)
                      _paint(
                        GridPane.letters,
                        Offset.zero,
                        ring,
                        width: frozenW,
                      ),
                    Expanded(
                      child: _paint(
                        GridPane.letters,
                        Offset(frozenW + _pan.dx, 0),
                        ring,
                      ),
                    ),
                  ],
                ),
              ),
              if (frozenH > 0)
                SizedBox(
                  height: frozenH,
                  child: Row(
                    children: <Widget>[
                      _paint(
                        GridPane.numbers,
                        Offset.zero,
                        ring,
                        width: kRowHeaderWidth,
                      ),
                      if (frozenW > 0)
                        _paint(
                          GridPane.cells,
                          Offset.zero,
                          ring,
                          width: frozenW,
                        ),
                      Expanded(
                        child: _paint(
                          GridPane.cells,
                          Offset(frozenW + _pan.dx, 0),
                          ring,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Row(
                  children: <Widget>[
                    _paint(
                      GridPane.numbers,
                      Offset(0, frozenH + _pan.dy),
                      ring,
                      width: kRowHeaderWidth,
                    ),
                    if (frozenW > 0)
                      _paint(
                        GridPane.cells,
                        Offset(0, frozenH + _pan.dy),
                        ring,
                        width: frozenW,
                      ),
                    Expanded(
                      child: _paint(
                        GridPane.cells,
                        Offset(frozenW + _pan.dx, frozenH + _pan.dy),
                        ring,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// One pane, clipped to itself so a cell half in it is half drawn rather
  /// than spilling into the pane beside it.
  Widget _paint(GridPane pane, Offset at, Rect? ring, {double? width}) {
    final paint = ClipRect(
      child: CustomPaint(
        painter: GridPainter(
          table: widget.table,
          geometry: _geometry,
          pane: pane,
          offset: at,
          selected: widget.selected,
          ring: pane == GridPane.cells ? ring : null,
          matches: widget.matches,
          commented: widget.commented,
          raggedRows: widget.raggedRows,
          face: widget.face,
          textScale: widget.textScale,
        ),
        size: Size.infinite,
      ),
    );
    return width == null ? paint : SizedBox(width: width, child: paint);
  }
}
