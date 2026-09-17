import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../constants/gooey_fab.dart'
    show kGooAlphaThresholdMatrix, kGooBlurSigma;
import '../../../painting/grid_painter.dart';
import '../../../painting/cell_goo_painter.dart';
import '../../../theme/colors.dart';
import '../../../theme/easings.dart';
import '../../../theme/feedback.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';
import 'sheet_geometry.dart';
import 'spine_table.dart' show SheetCell, SheetFace;

/// On a move, when the lit letter and number set off and arrive, as shares of
/// the journey: the edge on the side the choice is going leads, the other
/// follows, and the two meet again at the new cell.
const kGridLitLeadStart = 0.1;
const kGridLitLeadEnd = 0.62;
const kGridLitTrailStart = 0.24;
const kGridLitTrailEnd = 0.86;

/// On a first choice, when the lit letter and number spread out from the
/// middle of their column and row; on a choice let go, when they have drawn
/// back in to it.
const kGridLitSpreadStart = 0.08;
const kGridLitSpreadEnd = 0.72;
const kGridLitDrawInEnd = 0.6;

/// How quickly the ring fades as it draws into the goo on a choice let go,
/// and as it opens out of the goo on its way in.
const kGridRingLetGo = 0.35;
const kGridRingFadeIn = 0.15;

/// How long the goo takes to come up to full strength as a choice sets off
/// from a cell at rest, where there was a ring and no fill.
const kGridFillRise = 0.25;

/// A request to bring a cell into view.
///
/// Every request is its own object, so asking for the same cell twice is
/// still asking twice: a jump back to a row the reader has since scrolled
/// away from is carried out rather than taken for the request before it.
class SheetReveal {
  SheetReveal(this.cell, {this.toTop = false});

  final SheetCell cell;

  /// True when the row should come to the top of the grid, as far as the
  /// sheet has rows below it to allow, which is what a jump to a place in
  /// the document means. False for the shortest push that puts the cell on
  /// screen, which is what showing somebody a cell means.
  final bool toTop;
}

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

  /// A cell the grid should bring into view, such as the one a find landed
  /// on or the row a dog ear jumps to.
  final SheetReveal? reveal;

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

  /// True while the grid is gliding on its own to show a cell, rather than
  /// carrying on after a flick.
  bool _showing = false;

  /// The choice on its way from one place to the next.
  late final AnimationController _ringMove;

  /// The ring opens on the goo spring timed over the whole of its settling,
  /// so it comes to rest inside the part of the journey it has rather than
  /// being cut off still moving when the journey ends.
  final SpringCurve _ringCurve = SpringCurve(
    AppSprings.goo,
    duration: springDuration(AppSprings.goo),
  );

  /// Where the body set off from, which is null for a first choice, and the
  /// cell it is going to, which is null for a choice let go. At rest, the cell
  /// the ring sits on.
  Rect? _ringFrom;
  Rect? _ringTo;

  /// How round the body was, how strong the goo was, how much ring there
  /// was, and what was lit along the bands, all at the moment it set off.
  double _fromCorner = kCellGooCellCorner;
  double _fillFrom = 0;
  double _ringStrengthFrom = 0;
  Rect? _litFrom;

  @override
  void initState() {
    super.initState();
    _pan = widget.startAt;
    _glideX = AnimationController.unbounded(vsync: this)
      ..addListener(
        () => _pushTo(Offset(_glideX.value, _pan.dy), byHand: !_showing),
      );
    _glideY = AnimationController.unbounded(vsync: this)
      ..addListener(
        () => _pushTo(Offset(_pan.dx, _glideY.value), byHand: !_showing),
      );
    _ringMove = AnimationController(vsync: this, duration: kGridRingMove)
      ..addListener(_repaint);
    _ringTo = _rectOf(widget.selected);
  }

  @override
  void didUpdateWidget(SheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) {
      _geometry = SheetGeometry.of(widget.table);
      // The same sheet read again keeps its place, and a smaller one keeps
      // as much of it as it has room for.
      final limit = _limit;
      _pan = Offset(_pan.dx.clamp(0.0, limit.dx), _pan.dy.clamp(0.0, limit.dy));
      // Where the choice was, or was going, on the new sheet's measures, so
      // a journey under way carries on and a choice that changed in the same
      // breath still travels from somewhere.
      _ringTo = _rectOf(oldWidget.selected);
    }
    if (oldWidget.selected != widget.selected) _moveRing();
    final reveal = widget.reveal;
    if (reveal != null && reveal != oldWidget.reveal) {
      // After this frame rather than during it: bringing a cell into view
      // moves the reader's place in the document, and the document cannot be
      // told it has moved while the screen showing it is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bring(reveal.cell, toTop: reveal.toTop);
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

  static double _stage(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  bool get _journeying => _ringMove.isAnimating;

  // ------------------------------------------------------------- the choice

  /// The goo sits a little inside the cells it travels between. Worked out
  /// from the middle rather than by deflating, so a body that has dried to
  /// nothing comes back out as nothing rather than as a rectangle turned
  /// inside out.
  static Rect _inset(Rect cell) => Rect.fromCenter(
    center: cell.center,
    width: math.max(0, cell.width - 2 * kGridGooInset),
    height: math.max(0, cell.height - 2 * kGridGooInset),
  );

  static Rect _outset(Rect body) => Rect.fromCenter(
    center: body.center,
    width: math.max(0, body.width) + 2 * kGridGooInset,
    height: math.max(0, body.height) + 2 * kGridGooInset,
  );

  /// The body at this moment, in the cells' own measure.
  CellGooShape? _bodyNow() {
    final from = _ringFrom;
    final to = _ringTo;
    if (!_journeying) return null;
    final body = CellGooPainter.bodyAt(
      from: from == null ? null : _inset(from),
      to: to == null ? null : _inset(to),
      t: _ringMove.value,
      fromCorner: _fromCorner,
    );
    return body == null
        ? null
        : (rect: _outset(body.rect), corner: body.corner);
  }

  /// The choice never jumps between cells. It sets off from wherever it is,
  /// even half way to somewhere else, and everything that shows it (the goo,
  /// the ring, the lit letter and number) goes with it.
  void _moveRing() {
    final to = _rectOf(widget.selected);
    final body = _bodyNow();
    final from = _journeying ? body?.rect : _ringTo;
    final ring = _ringNow();
    final fill = _journeying ? _fillNow() : 0.0;
    final lit = _litNow();
    _ringMove.stop();
    if (from == null && to == null) {
      setState(() {
        _ringFrom = null;
        _ringTo = null;
        _litFrom = null;
      });
      return;
    }
    setState(() {
      _ringFrom = from;
      _ringTo = to;
      _fromCorner = body?.corner ?? kCellGooCellCorner;
      _fillFrom = from == null ? 1 : fill;
      _ringStrengthFrom = ring?.strength ?? 0;
      _litFrom = lit;
    });
    _ringMove.duration = from == null
        ? kGridRingAppear
        : to == null
        ? kGridRingLeave
        : kGridRingMove;
    _ringMove.forward(from: 0);
  }

  /// How strong the goo is at this moment.
  ///
  /// It comes up as the ring draws into it, because a cell at rest wears a
  /// ring and no fill, and it gives way to the ring again as it arrives. A
  /// choice let go never gives way: it dries up instead.
  double _fillNow() {
    if (!_journeying) return 0;
    final t = _ringMove.value;
    final rise = ui.lerpDouble(_fillFrom, 1, _stage(t, 0, kGridFillRise))!;
    if (_ringTo == null) return rise;
    final handover = t < 1 - kGridGooHandover
        ? 1.0
        : ((1 - t) / kGridGooHandover).clamp(0.0, 1.0);
    return rise * handover;
  }

  /// Where the ring is at this moment and how much of it there is, or null
  /// while the goo alone is carrying the choice.
  ///
  /// The goo leads and the ring follows it: it draws into the goo as the
  /// choice sets off, there is no ring anywhere while the body is crossing,
  /// and it opens out of the goo once the goo has reached the new cell.
  ({Rect rect, double strength})? _ringNow() {
    final to = _ringTo;
    final from = _ringFrom;
    if (!_journeying) return to == null ? null : (rect: to, strength: 1);
    final t = _ringMove.value;
    if (from != null) {
      final letGo = to == null ? kGridRingLetGo : kCellGooGatherEnd;
      if (t < letGo) {
        final strength =
            _ringStrengthFrom * (1 - easeOutCubic.transform(t / letGo));
        final body = _bodyNow();
        if (strength > 0 && body != null) {
          return (rect: body.rect, strength: strength);
        }
      }
    }
    if (to == null) return null;
    final opensAt = from == null ? kCellGooCondenseEnd : kCellGooArriveStart;
    if (t < opensAt) return null;
    final share = _stage(t, opensAt, 1);
    final open = _ringCurve.transform(share);
    final seed = Rect.fromCenter(
      center: to.center,
      width: to.height * kGridRingSeed,
      height: to.height * kGridRingSeed,
    );
    final rect = Rect.lerp(seed, to, open)!;
    // A little past the cell before it settles, the way a drop spreads.
    final swell = kGridRingSwell * math.sin(math.pi * open.clamp(0.0, 1.0));
    return (
      rect: rect.inflate(swell),
      strength: (share / kGridRingFadeIn).clamp(0.0, 1.0),
    );
  }

  /// The stretch of letters and numbers lit at this moment, and how round its
  /// ends are.
  ///
  /// On a move it crawls: the edge on the side the choice is going sets off
  /// first and arrives first, and the other edge follows it in. A first
  /// choice spreads out from the middle of its column and row, and a choice
  /// let go draws back in to it.
  ({Rect span, double round})? _litSpanNow() {
    final to = _ringTo;
    if (!_journeying) return to == null ? null : (span: to, round: 0);
    final t = _ringMove.value;
    final from = _litFrom;
    if (to == null) {
      if (from == null) return null;
      final share = easeInOutCubic.transform(_stage(t, 0, kGridLitDrawInEnd));
      return (
        span: Rect.lerp(
          from,
          Rect.fromCenter(center: from.center, width: 0, height: 0),
          share,
        )!,
        round: kGridLitRound * math.sin(math.pi * share),
      );
    }
    if (from == null) {
      final share = easeOutCubic.transform(
        _stage(t, kGridLitSpreadStart, kGridLitSpreadEnd),
      );
      return (
        span: Rect.lerp(
          Rect.fromCenter(center: to.center, width: 0, height: 0),
          to,
          share,
        )!,
        round: kGridLitRound * math.sin(math.pi * share),
      );
    }
    final lead = easeInOutCubic.transform(
      _stage(t, kGridLitLeadStart, kGridLitLeadEnd),
    );
    final trail = easeInOutCubic.transform(
      _stage(t, kGridLitTrailStart, kGridLitTrailEnd),
    );
    final across = to.center.dx >= from.center.dx;
    final down = to.center.dy >= from.center.dy;
    double edge(double a, double b, bool leading) =>
        ui.lerpDouble(a, b, leading ? lead : trail)!;
    return (
      span: Rect.fromLTRB(
        edge(from.left, to.left, !across),
        edge(from.top, to.top, !down),
        edge(from.right, to.right, across),
        edge(from.bottom, to.bottom, down),
      ),
      round: kGridLitRound * math.sin(math.pi * (lead + trail) / 2),
    );
  }

  Rect? _litNow() => _litSpanNow()?.span;

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
    _showing = false;
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
    _showing = false;
  }

  /// Takes the grid to [cell]: its row to the top when [toTop], and
  /// otherwise by the shortest push that puts it on screen.
  ///
  /// It glides there rather than cutting, so a find that lands somewhere else
  /// in the sheet carries you to it and you can see which way you went. The
  /// glide is a spring that sets off at whatever speed the grid already has,
  /// so a run of requests, such as a thumb scrubbing the fore edge, is
  /// followed in one smooth movement rather than started over from rest at
  /// every step. Nothing moves when a cell to be shown is already in view: a
  /// find that jumped the grid about for a match you were already looking at
  /// would be a find that loses your place to tell you where it is.
  void _bring(SheetCell cell, {bool toTop = false}) {
    final rect = _rectOf(cell);
    if (rect == null || _view == Size.zero) return;
    final frozen = Offset(_geometry.frozenWidth, _geometry.frozenHeight);
    final gliding = _showing && (_glideX.isAnimating || _glideY.isAnimating);
    var x = gliding ? _glideTarget.dx : _pan.dx;
    var y = gliding ? _glideTarget.dy : _pan.dy;
    final left = rect.left - frozen.dx;
    final top = rect.top - frozen.dy;
    if (left < x) x = left;
    if (rect.right - frozen.dx > x + _view.width) {
      x = rect.right - frozen.dx - _view.width;
    }
    if (toTop) {
      y = top;
    } else {
      if (top < y) y = top;
      if (rect.bottom - frozen.dy > y + _view.height) {
        y = rect.bottom - frozen.dy - _view.height;
      }
    }
    final limit = _limit;
    final target = Offset(x.clamp(0.0, limit.dx), y.clamp(0.0, limit.dy));
    // A flick still carrying the grid gives way to the request; a glide
    // already under way is bent towards the new place at the speed it has.
    if (!gliding) {
      _glideX.stop();
      _glideY.stop();
    }
    _glideTarget = target;
    _showing = true;
    _glide(_glideX, _pan.dx, target.dx);
    _glide(_glideY, _pan.dy, target.dy);
  }

  /// Where a glide the grid is making on its own is headed.
  Offset _glideTarget = Offset.zero;

  void _glide(AnimationController axis, double from, double to) {
    if ((to - from).abs() < 0.5 && !axis.isAnimating) return;
    final speed = axis.isAnimating ? axis.velocity : 0.0;
    axis
      ..value = from
      ..animateWith(
        SpringSimulation(
          AppSprings.reveal,
          from,
          to,
          speed,
          tolerance: const Tolerance(distance: 0.05, velocity: 1),
          // Exactly where it was sent once it is close enough to stop, so
          // the sheet never rests a fraction of a pixel off its own grid.
          snapToEnd: true,
        ),
      );
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
        final shown = _Shown(
          ring: _ringNow(),
          lit: _litSpanNow(),
          body: _journeying ? (from: _ringFrom, to: _ringTo) : null,
          fill: _fillNow(),
        );
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
                      shown,
                      width: kRowHeaderWidth,
                    ),
                    if (frozenW > 0)
                      _paint(
                        GridPane.letters,
                        Offset.zero,
                        shown,
                        width: frozenW,
                      ),
                    Expanded(
                      child: _paint(
                        GridPane.letters,
                        Offset(frozenW + _pan.dx, 0),
                        shown,
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
                        shown,
                        width: kRowHeaderWidth,
                      ),
                      if (frozenW > 0)
                        _paint(
                          GridPane.cells,
                          Offset.zero,
                          shown,
                          width: frozenW,
                        ),
                      Expanded(
                        child: _paint(
                          GridPane.cells,
                          Offset(frozenW + _pan.dx, 0),
                          shown,
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
                      shown,
                      width: kRowHeaderWidth,
                    ),
                    if (frozenW > 0)
                      _paint(
                        GridPane.cells,
                        Offset(0, frozenH + _pan.dy),
                        shown,
                        width: frozenW,
                      ),
                    Expanded(
                      child: _paint(
                        GridPane.cells,
                        Offset(frozenW + _pan.dx, frozenH + _pan.dy),
                        shown,
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

  /// The body of goo that carries the choice, over one pane of cells.
  ///
  /// It gathers out of the cell being left, crosses the sheet trailing a
  /// thread, and opens into the cell being chosen, the same journey the desk's
  /// tabs make, so a choice reads as one thing moving rather than a ring
  /// vanishing in one place and turning up in another. Blurred and cut at a
  /// threshold, which is what makes circles into one body. It is laid over
  /// every pane of cells, frozen ones included, so a choice in a header row
  /// is carried the same way as one in the body of the sheet.
  Widget _goo(Offset at, _Shown shown) {
    final body = shown.body;
    if (body == null || shown.fill <= 0) return const SizedBox.shrink();
    final from = body.from;
    final to = body.to;
    return IgnorePointer(
      child: ClipRect(
        child: Opacity(
          opacity: shown.fill.clamp(0.0, 1.0),
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(kGooAlphaThresholdMatrix),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: kGooBlurSigma,
                sigmaY: kGooBlurSigma,
                tileMode: TileMode.decal,
              ),
              child: CustomPaint(
                painter: CellGooPainter(
                  from: from == null ? null : _inset(from.shift(-at)),
                  to: to == null ? null : _inset(to.shift(-at)),
                  fromCorner: _fromCorner,
                  t: _ringMove.value,
                  colour: AppColors.accentMuted,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One pane, clipped to itself so a cell half in it is half drawn rather
  /// than spilling into the pane beside it.
  Widget _paint(GridPane pane, Offset at, _Shown shown, {double? width}) {
    Widget paint = ClipRect(
      child: CustomPaint(
        painter: GridPainter(
          table: widget.table,
          geometry: _geometry,
          pane: pane,
          offset: at,
          lit: shown.lit?.span,
          litRound: shown.lit?.round ?? 0,
          ring: pane == GridPane.cells ? shown.ring?.rect : null,
          ringStrength: shown.ring?.strength ?? 0,
          matches: widget.matches,
          commented: widget.commented,
          raggedRows: widget.raggedRows,
          face: widget.face,
          textScale: widget.textScale,
        ),
        size: Size.infinite,
      ),
    );
    if (pane == GridPane.cells && shown.body != null) {
      paint = Stack(
        fit: StackFit.expand,
        children: <Widget>[paint, _goo(at, shown)],
      );
    }
    return width == null ? paint : SizedBox(width: width, child: paint);
  }
}

/// Everything that shows the choice, worked out once for a frame and handed
/// to every pane, so the panes cannot disagree about where it is.
class _Shown {
  const _Shown({
    required this.ring,
    required this.lit,
    required this.body,
    required this.fill,
  });

  final ({Rect rect, double strength})? ring;
  final ({Rect span, double round})? lit;
  final ({Rect? from, Rect? to})? body;
  final double fill;
}
