import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../constants/gooey_fab.dart'
    show kGooAlphaThresholdMatrix, kGooBlurSigma;
import '../../../painting/grid_painter.dart';
import '../../../painting/cell_goo_painter.dart';
import '../../../theme/colors.dart';
import '../../../theme/feedback.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';
import 'sheet_choice.dart';
import 'sheet_geometry.dart';
import 'spine_table.dart' show SheetCell, SheetFace;

/// A request to bring a cell into view.
///
/// Every request is its own object, so asking for the same cell twice is
/// still asking twice: a jump back to a row the reader has since scrolled
/// away from is carried out rather than taken for the request before it.
class SheetReveal {
  SheetReveal(this.cell, {this.toTop = false});

  final SheetCell cell;

  /// True when the row should come to the top of the grid, as far as the
  /// sheet has rows below it to allow, which is what a jump to a place in the
  /// document means. The grid keeps whatever columns it is showing, because a
  /// jump is to a row and the reader is still reading across. False for the
  /// shortest push that puts the cell on screen, which is what showing
  /// somebody a cell means.
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
    this.coveredBelow = 0,
  });

  final TableBlock table;

  /// The cell the reader has chosen, which the choice travels to.
  final SheetCell? selected;
  final ValueChanged<SheetCell> onSelect;

  final Set<SheetCell> matches;
  final Set<SheetCell> commented;
  final Set<int> raggedRows;

  /// A cell the grid should bring into view, such as the one a find landed
  /// on or the row a dog ear jumps to.
  final SheetReveal? reveal;

  /// True while the reading is pinned, when the grid holds still like the
  /// pages do and claims no touches, so a tap goes on to the reader.
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

  /// How much of the foot of the grid something is laid over, such as the
  /// bar showing the chosen cell, so a cell brought into view is brought
  /// clear of it rather than under it.
  final double coveredBelow;

  @override
  State<SheetGrid> createState() => SheetGridState();
}

class SheetGridState extends State<SheetGrid> with TickerProviderStateMixin {
  late SheetGeometry _geometry = SheetGeometry.of(widget.table);

  /// How far the sheet has been pushed, in its own space. Past either end
  /// only while it is pulled against that end or is springing back from it.
  Offset _pan = Offset.zero;

  /// The room the scrolling part of the grid has, which the pan is held
  /// inside. It is nought until the first layout.
  Size _view = Size.zero;

  /// As much of the file's frozen panes as there is room to hold, which on a
  /// phone can be less than the file asks for.
  late Size _frozen = Size(_geometry.frozenWidth, _geometry.frozenHeight);

  late final AnimationController _glideX;
  late final AnimationController _glideY;

  /// True while the grid is gliding on its own to show a cell, rather than
  /// carrying on after a flick.
  bool _showing = false;

  /// Where a glide the grid is making on its own is headed.
  Offset _glideTarget = Offset.zero;

  /// The choice of cell, and the clock it moves on, in seconds. The clock
  /// only runs while something is moving.
  late final SheetChoice _choice = SheetChoice(_rectOf(widget.selected));

  /// The cell the goo is measured from: the one chosen, or the one last
  /// chosen while it is being let go.
  late SheetCell? _anchor = widget.selected;

  /// The cells a find has lit, kept while their wash fades out after the find
  /// is put away, and how much of the wash shows.
  late Set<SheetCell> _matchesShown = widget.matches;
  late final SpringValue _matchFade = SpringValue(
    widget.matches.isEmpty ? 0 : 1,
    tolerance: SpringValue.shareTolerance,
  );
  late final Ticker _ticker;
  double _now = 0;
  double _started = 0;

  @override
  void initState() {
    super.initState();
    _pan = widget.startAt;
    _glideX = AnimationController.unbounded(vsync: this)
      ..addListener(
        () => _pushTo(
          Offset(_glideX.value, _pan.dy),
          byHand: !_showing,
          over: true,
        ),
      );
    _glideY = AnimationController.unbounded(vsync: this)
      ..addListener(
        () => _pushTo(
          Offset(_pan.dx, _glideY.value),
          byHand: !_showing,
          over: true,
        ),
      );
    _ticker = createTicker(_tick);
    // A grid made for a cell that has already been asked for, such as a find
    // landing on another sheet, goes to it as soon as it has been laid out.
    final reveal = widget.reveal;
    if (reveal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _bring(reveal.cell, toTop: reveal.toTop);
        });
      });
    }
  }

  @override
  void didUpdateWidget(SheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.table != widget.table) {
      final measured = SheetGeometry.of(widget.table);
      final same =
          measured.size == _geometry.size &&
          measured.columnCount == _geometry.columnCount &&
          measured.rowCount == _geometry.rowCount;
      _geometry = measured;
      // The same sheet read again keeps its place and whatever is moving on
      // it. A different one is measured afresh.
      if (!same) {
        final limit = _limit;
        _pan = Offset(
          _pan.dx.clamp(0.0, limit.dx),
          _pan.dy.clamp(0.0, limit.dy),
        );
        _choice.settleOn(_rectOf(oldWidget.selected));
      }
    }
    if (oldWidget.selected != widget.selected) {
      final from = _anchor;
      final to = widget.selected;
      // The goo is carried from the last cell's pane to the new one's, so
      // that where it is on screen does not change as it changes panes.
      final rebase = to == null ? Offset.zero : _shiftOf(to) - _shiftOf(from);
      final acrossPanes =
          from != null &&
          to != null &&
          ((from.row < _geometry.frozenRows) !=
                  (to.row < _geometry.frozenRows) ||
              (from.column < _geometry.frozenColumns) !=
                  (to.column < _geometry.frozenColumns));
      _choice.choose(
        _rectOf(to),
        _now,
        rebase: rebase,
        acrossPanes: acrossPanes,
      );
      if (to != null) _anchor = to;
      _run();
    }
    if (!setEquals(oldWidget.matches, widget.matches)) {
      if (widget.matches.isNotEmpty) {
        _matchesShown = widget.matches;
        _matchFade.sendTo(1, _now, AppSprings.gooRise);
      } else {
        _matchFade.sendTo(0, _now, AppSprings.gooSet);
      }
      _run();
    }
    final reveal = widget.reveal;
    if (reveal != null && reveal != oldWidget.reveal) {
      // After this frame rather than during it: bringing a cell into view
      // moves the reader's place in the document, and the document cannot be
      // told it has moved while the screen showing it is still being built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bring(reveal.cell, toTop: reveal.toTop);
      });
    }
    if (widget.locked && !oldWidget.locked && !_showing) {
      // Held where it is. A pull past an end still goes back to the end.
      _settleInside();
    }
    if (widget.coveredBelow < oldWidget.coveredBelow) {
      // What was laid over the foot has gone, and the room it made with it:
      // a sheet pushed into that room settles back to its own end.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_glideY.isAnimating && _pan.dy > _limit.dy) {
          _settleInside();
        }
      });
    }
  }

  @override
  void dispose() {
    _glideX.dispose();
    _glideY.dispose();
    _ticker.dispose();
    super.dispose();
  }

  Rect? _rectOf(SheetCell? cell) =>
      cell == null ? null : _geometry.rectOf(widget.table, cell);

  // ------------------------------------------------------------- the choice

  bool get _stirring => _choice.moving || !_matchFade.restingAt(_now);

  void _run() {
    if (!_stirring || _ticker.isActive) return;
    _started = _now;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    _now = _started + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _choice.step(_now);
    if (_matchFade.restingAt(_now) && _matchFade.target == 0) {
      _matchesShown = const <SheetCell>{};
    }
    if (!_stirring) _ticker.stop();
    if (mounted) setState(() {});
  }

  /// How far the pane [cell] is in has been pushed: the whole pan for a cell
  /// in the part that scrolls, none of it on an axis the cell is frozen on.
  Offset _shiftOf(SheetCell? cell) {
    if (cell == null) return Offset.zero;
    return Offset(
      cell.column < _geometry.frozenColumns ? 0 : _pan.dx,
      cell.row < _geometry.frozenRows ? 0 : _pan.dy,
    );
  }

  // -------------------------------------------------------------- the pan

  /// How far the sheet can be pushed. While something is laid over the foot
  /// of the grid, the sheet can be pushed on by that much, so its last rows
  /// can be brought up clear of it.
  Offset get _limit =>
      _geometry.limitFor(
        Size(_view.width + kRowHeaderWidth, _view.height + kGridHeaderHeight),
        frozen: _frozen,
      ) +
      Offset(0, widget.coveredBelow);

  /// Moves the sheet to [next]. Held inside the sheet unless [over], which
  /// is for the pull against an end and the spring back from it.
  void _pushTo(Offset next, {bool byHand = true, bool over = false}) {
    final limit = _limit;
    final held = over
        ? next
        : Offset(next.dx.clamp(0.0, limit.dx), next.dy.clamp(0.0, limit.dy));
    if (held == _pan) return;
    setState(() => _pan = held);
    widget.onPanned?.call(
      held,
      _geometry.rowAt(math.max(0, held.dy) + _frozen.height),
      byHand,
    );
  }

  void _drag(DragUpdateDetails details) {
    _stopGliding();
    final limit = _limit;
    final push = -details.delta;
    _pushTo(
      Offset(
        _pan.dx + _resisted(_pan.dx, push.dx, limit.dx),
        _pan.dy + _resisted(_pan.dy, push.dy, limit.dy),
      ),
      over: true,
    );
  }

  /// A push past either end of the sheet gives way less the further it goes,
  /// so the end can be felt without being a wall.
  static double _resisted(double at, double push, double end) {
    final past = at < 0 ? -at : (at > end ? at - end : 0.0);
    final outward = (at <= 0 && push < 0) || (at >= end && push > 0);
    if (!outward) return push;
    return push * kGridPullGive * (1 - past / kGridPullMax).clamp(0.05, 1.0);
  }

  void _fling(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final limit = _limit;
    _showing = false;
    _glideAxis(
      _glideX,
      _pan.dx,
      _released(_pan.dx, -velocity.dx, limit.dx),
      limit.dx,
    );
    _glideAxis(
      _glideY,
      _pan.dy,
      _released(_pan.dy, -velocity.dy, limit.dy),
      limit.dy,
    );
  }

  /// The speed a sheet is let go at. Past an end and still being pulled
  /// outward, the sheet was only moving at the share of the finger's speed
  /// the pull gave it, and it carries on at that, not at the finger's.
  static double _released(double at, double velocity, double end) {
    final past = at < 0 ? -at : (at > end ? at - end : 0.0);
    final outward = (at < 0 && velocity < 0) || (at > end && velocity > 0);
    if (!outward) return velocity;
    return velocity *
        kGridPullGive *
        (1 - past / kGridPullMax).clamp(0.05, 1.0);
  }

  /// A finger put down on a sheet that is still gliding catches it, the way
  /// a hand stops a turning page, and the tap that finger makes is taken as
  /// the catch rather than as a choice.
  bool _caught = false;

  void _touch(DragDownDetails details) {
    final moving = _glideX.isAnimating || _glideY.isAnimating;
    // Only a flick is caught. A glide the grid is making to show a cell stops
    // under the finger too, but the tap still chooses, since a reader
    // tapping cell after cell should not lose every other tap.
    _caught = moving && !_showing;
    if (moving) _stopGliding();
  }

  /// A touch that turned out to be neither a push nor a tap, or a tap that
  /// only caught the sheet: a sheet it left past an end goes back.
  void _untouch() {
    final limit = _limit;
    final outside =
        _pan.dx < 0 || _pan.dx > limit.dx || _pan.dy < 0 || _pan.dy > limit.dy;
    if (outside && !_glideX.isAnimating && !_glideY.isAnimating) {
      _settleInside();
    }
  }

  void _glideAxis(
    AnimationController axis,
    double at,
    double velocity,
    double end,
  ) {
    final outside = at < 0 || at > end;
    final flung = velocity.abs() > kGridFlingFrom;
    if (!outside && !flung) return;
    axis
      ..value = at
      ..animateWith(
        _EdgeGlide(position: at, velocity: flung ? velocity : 0, end: end),
      );
  }

  /// Takes a sheet left pulled past an end back inside it.
  void _settleInside() {
    final limit = _limit;
    _showing = false;
    _glideAxis(_glideX, _pan.dx, 0, limit.dx);
    _glideAxis(_glideY, _pan.dy, 0, limit.dy);
  }

  void _stopGliding() {
    _glideX.stop();
    _glideY.stop();
    _showing = false;
  }

  /// Takes the grid to [cell]: its row to the top when [toTop], and
  /// otherwise by the shortest push that puts it on screen, clear of anything
  /// laid over the foot of the grid.
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
    final gliding = _showing && (_glideX.isAnimating || _glideY.isAnimating);
    var x = gliding ? _glideTarget.dx : _pan.dx;
    var y = gliding ? _glideTarget.dy : _pan.dy;
    final top = rect.top - _frozen.height;
    // A cell in a frozen row is on screen whatever the pan down is, and one
    // in a frozen column whatever the pan across is, so choosing one moves
    // nothing on that axis. Throwing the reader back to the top to show them
    // a header they could already see would lose their place.
    final frozenRow = cell.row < _geometry.frozenRows;
    final frozenColumn = cell.column < _geometry.frozenColumns;
    if (toTop) {
      if (!frozenRow) y = top;
    } else {
      // A cell wider than the view shows its start, and one taller than what
      // is left of it shows its top: the end of a thing is no use without
      // its beginning.
      if (!frozenColumn) {
        final left = rect.left - _frozen.width;
        if (rect.right - _frozen.width > x + _view.width) {
          x = rect.right - _frozen.width - _view.width;
        }
        if (left < x) x = left;
      }
      if (!frozenRow) {
        final seen = math.max(kGridRowMin, _view.height - widget.coveredBelow);
        if (rect.bottom - _frozen.height > y + seen) {
          y = rect.bottom - _frozen.height - seen;
        }
        if (top < y) y = top;
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
    if (_caught) {
      _caught = false;
      _untouch();
      return;
    }
    final inGrid = Offset(
      local.dx - kRowHeaderWidth,
      local.dy - kGridHeaderHeight,
    );
    if (inGrid.dx < 0 || inGrid.dy < 0) return;
    final x = inGrid.dx <= _frozen.width ? inGrid.dx : inGrid.dx + _pan.dx;
    final y = inGrid.dy <= _frozen.height ? inGrid.dy : inGrid.dy + _pan.dy;
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
        final frozen = Size(frozenW, frozenH);
        if (view != _view || frozen != _frozen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _view = view;
              _frozen = frozen;
            });
          });
        }
        final frame = _choice.frameAt(_now);
        final across = frozenW + _pan.dx;
        final down = frozenH + _pan.dy;
        final grid = Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: kGridHeaderHeight,
                  child: Row(
                    children: <Widget>[
                      _paint(
                        GridPane.corner,
                        Offset.zero,
                        frame,
                        width: kRowHeaderWidth,
                      ),
                      if (frozenW > 0)
                        _paint(
                          GridPane.letters,
                          Offset.zero,
                          frame,
                          width: frozenW,
                        ),
                      Expanded(
                        child: _paint(
                          GridPane.letters,
                          Offset(across, 0),
                          frame,
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
                          frame,
                          width: kRowHeaderWidth,
                        ),
                        if (frozenW > 0)
                          _paint(
                            GridPane.cells,
                            Offset.zero,
                            frame,
                            width: frozenW,
                          ),
                        Expanded(
                          child: _paint(
                            GridPane.cells,
                            Offset(across, 0),
                            frame,
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
                        Offset(0, down),
                        frame,
                        width: kRowHeaderWidth,
                      ),
                      if (frozenW > 0)
                        _paint(
                          GridPane.cells,
                          Offset(0, down),
                          frame,
                          width: frozenW,
                        ),
                      Expanded(
                        child: _paint(
                          GridPane.cells,
                          Offset(across, down),
                          frame,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // One body of goo over every pane of cells, measured from the
            // pane of the cell it is going to, so it is seen to cross the
            // edge of a frozen pane rather than vanish at it.
            Positioned(
              left: kRowHeaderWidth,
              top: kGridHeaderHeight,
              right: 0,
              bottom: 0,
              child: _goo(frame),
            ),
          ],
        );
        // Under a lock the grid claims nothing, so a tap goes on to the
        // reader, which answers it with the way to unlock.
        if (widget.locked) return grid;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: _touch,
          onPanCancel: _untouch,
          onPanUpdate: _drag,
          onPanEnd: _fling,
          onTapUp: (details) => _tap(details.localPosition),
          child: grid,
        );
      },
    );
  }

  /// The goo that carries the choice, over all the cells.
  ///
  /// Blurred and cut at a threshold, which is what makes its shapes one body
  /// with a neck.
  Widget _goo(ChoiceFrame frame) {
    final goo = frame.goo;
    if (goo == null || frame.fill <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: Opacity(
          opacity: frame.fill,
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
                  goo: goo.shift(-_shiftOf(_anchor)),
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
  Widget _paint(GridPane pane, Offset at, ChoiceFrame frame, {double? width}) {
    final paint = ClipRect(
      child: CustomPaint(
        painter: GridPainter(
          table: widget.table,
          geometry: _geometry,
          pane: pane,
          offset: at,
          lit: frame.lit,
          litRound: frame.litRound,
          litStrength: frame.litStrength,
          ring: pane == GridPane.cells ? frame.ring : null,
          ringStrength: frame.ringStrength,
          matches: _matchesShown,
          matchStrength: _matchFade.valueAt(_now).clamp(0.0, 1.0),
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

/// A flick on one axis: carried on by friction inside the sheet and caught by
/// a spring at either end, which takes the speed it arrives with a little way
/// past the end and brings it back, rather than stopping it dead against the
/// edge. Starting outside the sheet, it is the spring back alone.
class _EdgeGlide extends Simulation {
  _EdgeGlide({
    required double position,
    required double velocity,
    required this.end,
  }) : super(tolerance: const Tolerance(distance: 0.05, velocity: 1)) {
    if (position < 0 || position > end) {
      _edgeAt = 0;
      _spring = ScrollSpringSimulation(
        _catch,
        position,
        position < 0 ? 0 : end,
        velocity,
        tolerance: tolerance,
      );
      return;
    }
    final friction = FrictionSimulation(kGridFriction, position, velocity);
    _friction = friction;
    final stop = friction.finalX;
    final edge = stop < 0 ? 0.0 : (stop > end ? end : null);
    if (edge == null) return;
    final at = friction.timeAtX(edge);
    if (!at.isFinite) return;
    _edgeAt = at;
    _spring = ScrollSpringSimulation(
      _catch,
      edge,
      edge,
      friction.dx(at),
      tolerance: tolerance,
    );
  }

  /// The catch at an end, the same shape as a list's bounce.
  static final _catch = SpringDescription.withDampingRatio(
    mass: 0.5,
    stiffness: 100,
    ratio: 1.1,
  );

  final double end;
  FrictionSimulation? _friction;
  ScrollSpringSimulation? _spring;
  double _edgeAt = double.infinity;

  @override
  double x(double time) {
    final spring = _spring;
    if (spring != null && time >= _edgeAt) return spring.x(time - _edgeAt);
    return _friction!.x(time);
  }

  @override
  double dx(double time) {
    final spring = _spring;
    if (spring != null && time >= _edgeAt) return spring.dx(time - _edgeAt);
    return _friction!.dx(time);
  }

  @override
  bool isDone(double time) {
    final spring = _spring;
    if (spring != null && time >= _edgeAt) {
      return spring.isDone(time - _edgeAt);
    }
    return _friction!.isDone(time);
  }
}
