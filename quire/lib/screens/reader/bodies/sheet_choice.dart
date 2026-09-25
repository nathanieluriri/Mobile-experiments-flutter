import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/physics.dart' show SpringDescription;

import '../../../painting/cell_goo_painter.dart';
import '../../../theme/metrics.dart';
import '../../../theme/springs.dart';

/// The fastest the choice crosses a sheet, in points a second. A far cell is
/// travelled to at no more than this rather than thrown at, which is what
/// keeps a long journey reading as goo and not as a flick.
const kChoiceTopSpeed = 1700.0;

/// The slowest a long journey is taken, as a share of the house springs'
/// stiffness. Speed is capped, but never so far that the choice arrives long
/// after the sheet that carried the reader to it has stopped.
const kChoiceSlowest = 0.45;

/// The size a drop dries to and condenses from: just big enough that the
/// blur and the threshold keep it whole, so what is seen coming and going is
/// the goo fading in and out, never a drop cut off part way at speed.
const kChoiceDropFloor = 26.0;

/// How far a cell has to be for the goo not to cross to it, and how far
/// short of it the goo condenses instead. Past a screen away the sheet glides
/// to the cell, and goo streaking across rows scrolling past it is a smear,
/// not a thing moving.
const kChoiceFar = 750.0;
const kChoiceReach = 96.0;

/// A spring made slower by [share] of its stiffness, keeping its shape.
SpringDescription _slowed(SpringDescription spring, double share) =>
    SpringDescription(
      mass: spring.mass,
      stiffness: spring.stiffness * share,
      damping: spring.damping * math.sqrt(share),
    );

/// Everything that shows the choice of cell at one moment.
class ChoiceFrame {
  const ChoiceFrame({
    this.goo,
    this.fill = 0,
    this.ring,
    this.ringStrength = 0,
    this.lit,
    this.litRound = 0,
    this.litStrength = 1,
  });

  /// The goo, and how much of it shows. Null once the choice is at rest,
  /// when a ring is all a chosen cell wears.
  final CellGoo? goo;
  final double fill;

  /// The ring round the goo, and how much of it there is.
  final Rect? ring;
  final double ringStrength;

  /// The stretch of letters and numbers lit, in the sheet's own space, and
  /// how round its ends are.
  final Rect? lit;
  final double litRound;

  /// How much of the lit stretch shows, which is less than all of it only
  /// while it fades from one place to another it cannot crawl to.
  final double litStrength;
}

/// The chosen cell, as something with weight.
///
/// Every part of it is a number on a spring: where the body is, what it
/// trails, how wide and tall and round it is, how much ring and how much goo
/// there is, and each edge of the lit letters and numbers. Nothing runs on a
/// clock of its own, so nothing is ever cut off part way, and a new choice
/// made while the last one is still moving sets every part off again from
/// where it is, at the speed it has.
///
/// A choice that moves gathers into a drop, crosses the sheet drawing a neck
/// behind it, and spreads into the new cell once it is nearly there. The ring
/// forms round the goo once the goo has spread, and the goo gives way to it.
/// A first choice condenses as a drop at the middle of the cell. A choice let
/// go draws the ring in to a drop that dries up where it is.
class SheetChoice {
  SheetChoice(Rect? cell) : _cell = cell {
    if (cell != null) _restOn(cell);
  }

  Rect? _cell;
  bool _moving = false;

  final _headX = SpringValue(0);
  final _headY = SpringValue(0);
  final _tailX = SpringValue(0);
  final _tailY = SpringValue(0);
  final _width = SpringValue(0);
  final _height = SpringValue(0);
  final _corner = SpringValue(0);
  final _fill = SpringValue(0, tolerance: SpringValue.shareTolerance);
  final _ring = SpringValue(0, tolerance: SpringValue.shareTolerance);
  final _left = SpringValue(0);
  final _top = SpringValue(0);
  final _right = SpringValue(0);
  final _bottom = SpringValue(0);
  final _litStrength = SpringValue(1, tolerance: SpringValue.shareTolerance);

  /// The size of a ring melting where it was, apart from the body's, which
  /// may be condensing somewhere else altogether.
  final _meltWidth = SpringValue(0);
  final _meltHeight = SpringValue(0);

  /// Where the lit stretch is to go once it has faded out where it was, for
  /// a move it cannot crawl: to a far cell, or across the edge of a frozen
  /// pane, which the bands cannot be seen to cross.
  Rect? _litSwapTo;

  /// True while the lit stretch is showing: a cell is chosen, or one has
  /// just been let go and its letter and number are still drawing in.
  bool _litShown = false;

  /// False while a first choice is still condensing, before it can spread.
  bool _condensed = true;

  /// True once the ring has been sent out of the goo for this choice.
  bool _set = false;

  /// Where a ring being let go of melts: the middle of the cell it was
  /// round. It draws in there rather than riding away on the goo, so what
  /// leaves the cell is goo and what stays behind is a ring going out.
  Offset _ringHome = Offset.zero;

  /// The size the body travels at, from the last cell it was going to, and
  /// that size on its way there, so moving between rows of different heights
  /// does not change the body's size in a single frame.
  double _radius = kCellGooBodyMax / 2;
  final _radiusNow = SpringValue(kCellGooBodyMax / 2);

  /// The cell chosen, in the sheet's own space.
  Rect? get cell => _cell;

  /// True from a change until everything has come to rest.
  bool get moving => _moving;

  List<SpringValue> get _all => <SpringValue>[
    _headX,
    _headY,
    _tailX,
    _tailY,
    _width,
    _height,
    _corner,
    _fill,
    _ring,
    _left,
    _top,
    _right,
    _bottom,
    _radiusNow,
    _litStrength,
    _meltWidth,
    _meltHeight,
  ];

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

  static double _radiusFor(Rect body) =>
      body.shortestSide.clamp(kCellGooBodyMin, kCellGooBodyMax) / 2;

  void _restOn(Rect cell) {
    final body = _inset(cell);
    _headX.jumpTo(cell.center.dx);
    _headY.jumpTo(cell.center.dy);
    _tailX.jumpTo(cell.center.dx);
    _tailY.jumpTo(cell.center.dy);
    _width.jumpTo(body.width);
    _height.jumpTo(body.height);
    _corner.jumpTo(kCellGooCellCorner);
    _fill.jumpTo(0);
    _ring.jumpTo(1);
    _left.jumpTo(cell.left);
    _top.jumpTo(cell.top);
    _right.jumpTo(cell.right);
    _bottom.jumpTo(cell.bottom);
    _radius = _radiusFor(body);
    _radiusNow.jumpTo(_radius);
    _litStrength.jumpTo(1);
    _litSwapTo = null;
    _litShown = true;
    _moving = false;
  }

  /// Puts the choice on [cell] at once, with nothing moving, for a sheet
  /// measured afresh.
  void settleOn(Rect? cell) {
    _cell = cell;
    if (cell == null) {
      _litShown = false;
      _moving = false;
      return;
    }
    _restOn(cell);
  }

  /// Chooses [cell], or lets the choice go when it is null, at [now].
  ///
  /// The goo is measured from the pane of the cell it is going to, since a
  /// frozen pane and the pane that scrolls put the same cell in different
  /// places. [rebase] is how far that measure moves from the last cell's
  /// pane to this one's, and the goo is carried across by it so that it is
  /// in the same place on screen as it was. [acrossPanes] is true when the
  /// two cells are either side of a frozen pane's edge, which the lit letters
  /// and numbers cannot be seen to crawl across.
  void choose(
    Rect? cell,
    double now, {
    Offset rebase = Offset.zero,
    bool acrossPanes = false,
  }) {
    final was = _cell;
    if (cell == was) return;
    // Where things are, read before the choice changes, since what is lit at
    // rest is the cell that was chosen. The lit stretch and a ring melting
    // stay in the sheet's own space, in the pane of the cell they belong to,
    // so they are read before the goo is carried across to the new pane.
    final litNow = _litAt(now);
    if (_set || !_moving) {
      final ring = _ringAt(now);
      _ringHome =
          ring?.center ?? Offset(_headX.valueAt(now), _headY.valueAt(now));
      _meltWidth.jumpTo(ring?.width ?? 0);
      _meltHeight.jumpTo(ring?.height ?? 0);
      final drop = kChoiceDropFloor + 2 * kGridGooInset;
      _meltWidth.sendTo(drop, now, AppSprings.gooRise);
      _meltHeight.sendTo(drop, now, AppSprings.gooRise);
    }
    for (final (value, by) in <(SpringValue, double)>[
      (_headX, rebase.dx),
      (_headY, rebase.dy),
      (_tailX, rebase.dx),
      (_tailY, rebase.dy),
    ]) {
      value.shiftBy(by, now);
    }
    final head = Offset(_headX.valueAt(now), _headY.valueAt(now));
    _cell = cell;
    _set = false;

    if (cell == null) {
      if (was == null && !_moving) return;
      // The body coasts to a stop from the speed it had rather than being
      // pinned where the finger let go of it, and dries up there.
      final coast =
          head + Offset(_headX.velocityAt(now), _headY.velocityAt(now)) * 0.12;
      _headX.sendTo(coast.dx, now, AppSprings.gooHead);
      _headY.sendTo(coast.dy, now, AppSprings.gooHead);
      _tailX.sendTo(coast.dx, now, AppSprings.gooTail);
      _tailY.sendTo(coast.dy, now, AppSprings.gooTail);
      _ring.sendTo(0, now, AppSprings.gooRise);
      _fill.sendTo(1, now, AppSprings.gooRise);
      _litSwapTo = null;
      _litStrength.sendTo(1, now, AppSprings.gooSet);
      if (litNow != null) {
        final middle = litNow.center;
        _left.sendTo(middle.dx, now, AppSprings.litTrail);
        _right.sendTo(middle.dx, now, AppSprings.litTrail);
        _top.sendTo(middle.dy, now, AppSprings.litTrail);
        _bottom.sendTo(middle.dy, now, AppSprings.litTrail);
      }
      _moving = true;
      step(now);
      return;
    }

    final body = _inset(cell);
    final goal = cell.center;
    if (!_moving && was == null) {
      // Nothing was chosen, so there is nothing to carry: a drop condenses
      // at the middle of the cell, fading in as it spreads.
      _headX.jumpTo(goal.dx);
      _headY.jumpTo(goal.dy);
      _tailX.jumpTo(goal.dx);
      _tailY.jumpTo(goal.dy);
      _width.jumpTo(kChoiceDropFloor);
      _height.jumpTo(kChoiceDropFloor);
      _corner.jumpTo(kChoiceDropFloor / 2);
      _fill.jumpTo(0);
      _ring.jumpTo(0);
      _left.jumpTo(goal.dx);
      _right.jumpTo(goal.dx);
      _top.jumpTo(goal.dy);
      _bottom.jumpTo(goal.dy);
      _condensed = false;
    } else {
      // Carried from wherever the body is. A drop that had nearly dried up
      // condenses again as it goes.
      _condensed =
          math.min(_width.valueAt(now), _height.valueAt(now)) >= _radius * 1.2;
    }
    _radius = _radiusFor(body);
    _radiusNow.sendTo(_radius, now, AppSprings.gooSpread);
    _litShown = true;

    // A cell a screen or more away, chosen while no goo shows: the old ring
    // melts where it was, and a drop condenses a little way short of the new
    // cell on the side the choice came from and flows in.
    var distance = (goal - head).distance;
    var litFrom = litNow;
    if (distance > kChoiceFar && _fill.valueAt(now) < 0.05) {
      final way = (goal - head) / distance;
      final start = goal - way * kChoiceReach;
      _headX.jumpTo(start.dx);
      _headY.jumpTo(start.dy);
      _tailX.jumpTo(start.dx);
      _tailY.jumpTo(start.dy);
      _width.jumpTo(kChoiceDropFloor);
      _height.jumpTo(kChoiceDropFloor);
      _corner.jumpTo(kChoiceDropFloor / 2);
      _fill.jumpTo(0);
      _condensed = true;
      distance = kChoiceReach;
      acrossPanes = true;
    }

    // A spring's top speed grows with the distance it has to go, so a long
    // journey is taken on softer springs of the same shape, down to a floor.
    final fastest = kChoiceTopSpeed / (0.42 * math.max(distance, 1));
    final share = (fastest * fastest / AppSprings.gooHead.stiffness).clamp(
      kChoiceSlowest,
      1.0,
    );
    final headSpring = _slowed(AppSprings.gooHead, share);
    final tailSpring = _slowed(AppSprings.gooTail, share);
    final lead = _slowed(AppSprings.litLead, share);
    final trail = _slowed(AppSprings.litTrail, share);

    _headX.sendTo(goal.dx, now, headSpring);
    _headY.sendTo(goal.dy, now, headSpring);
    _tailX.sendTo(goal.dx, now, tailSpring);
    _tailY.sendTo(goal.dy, now, tailSpring);
    _ring.sendTo(0, now, AppSprings.gooRise);
    _fill.sendTo(1, now, AppSprings.gooRise);

    // The lit stretch crawls: the edge on the side the choice is going
    // leads, the other follows it in. Where it cannot be seen to crawl, it
    // fades out where it is and fades in at the new cell instead.
    if (acrossPanes && litFrom != null) {
      _litSwapTo = cell;
      _litStrength.sendTo(0, now, AppSprings.gooRise);
    } else {
      _litSwapTo = null;
      _litStrength.sendTo(1, now, AppSprings.gooSet);
      final from =
          litFrom ?? Rect.fromCenter(center: goal, width: 0, height: 0);
      final across = cell.center.dx - from.center.dx;
      final down = cell.center.dy - from.center.dy;
      _left.sendTo(cell.left, now, across > 0 ? trail : lead);
      _right.sendTo(cell.right, now, across < 0 ? trail : lead);
      _top.sendTo(cell.top, now, down > 0 ? trail : lead);
      _bottom.sendTo(cell.bottom, now, down < 0 ? trail : lead);
    }
    _moving = true;
    step(now);
  }

  /// Looks at where everything has got to and sends on what depends on it:
  /// the body spreads once it is nearly at its cell, the ring forms once the
  /// body has spread, and the goo gives way once the ring has formed.
  void step(double now) {
    if (!_moving) return;
    final cell = _cell;
    final swap = _litSwapTo;
    if (swap != null && _litStrength.valueAt(now) < 0.03) {
      _left.jumpTo(swap.left);
      _right.jumpTo(swap.right);
      _top.jumpTo(swap.top);
      _bottom.jumpTo(swap.bottom);
      _litStrength.sendTo(1, now, AppSprings.gooSet);
      _litSwapTo = null;
    }
    final w = _width.valueAt(now);
    final h = _height.valueAt(now);
    if (cell != null) {
      final body = _inset(cell);
      final r = _radius;
      if (!_condensed && math.min(w, h) >= 2 * r * 0.8) _condensed = true;
      final head = Offset(_headX.valueAt(now), _headY.valueAt(now));
      final near =
          (head - cell.center).distance <
          math.max(6.0, body.shortestSide * 0.6);
      // Once the ring has formed round it the body stays spread, whatever a
      // spring still settling makes of the distance to the cell.
      if (_condensed && (near || _set)) {
        _width.sendTo(body.width, now, AppSprings.gooSpread);
        _height.sendTo(body.height, now, AppSprings.gooSpread);
        _corner.sendTo(kCellGooCellCorner, now, AppSprings.gooSpread);
      } else {
        _width.sendTo(2 * r, now, AppSprings.gooSpread);
        _height.sendTo(2 * r, now, AppSprings.gooSpread);
        _corner.sendTo(r, now, AppSprings.gooSpread);
      }
      final spread =
          near &&
          (w - body.width).abs() <= body.width * 0.2 &&
          (h - body.height).abs() <= body.height * 0.35;
      if (!_set && spread) {
        _set = true;
        _ring.sendTo(1, now, AppSprings.gooSet);
      }
      if (_set && _ring.valueAt(now) >= 0.5) {
        _fill.sendTo(0, now, AppSprings.gooGiveWay);
      }
    } else {
      // Let go: draw in to a drop, then dry up.
      final r = _radius;
      if (math.max(w, h) > 2 * r * 1.15) {
        _width.sendTo(2 * r, now, AppSprings.gooRise);
        _height.sendTo(2 * r, now, AppSprings.gooRise);
        _corner.sendTo(r, now, AppSprings.gooRise);
      } else {
        // It dries by fading. It draws in only as far as the threshold still
        // keeps it whole, so the eye sees the goo go and not a drop cut off
        // part way at speed.
        _width.sendTo(kChoiceDropFloor, now, AppSprings.gooSet);
        _height.sendTo(kChoiceDropFloor, now, AppSprings.gooSet);
        _corner.sendTo(kChoiceDropFloor / 2, now, AppSprings.gooSet);
        _fill.sendTo(0, now, AppSprings.gooSet);
      }
    }
    if (_all.every((value) => value.restingAt(now))) {
      if (cell == null) {
        _litShown = false;
        _moving = false;
      } else if (_set) {
        _restOn(cell);
      }
    }
  }

  /// The ring's rectangle at [now]: round the goo once it has formed, and
  /// drawing in where it was while it is being let go of.
  Rect? _ringAt(double now) {
    if (!_moving) return _cell;
    final body = _outset(
      Rect.fromCenter(
        center: _set
            ? Offset(_headX.valueAt(now), _headY.valueAt(now))
            : _ringHome,
        width: math.max(0.0, _width.valueAt(now)),
        height: math.max(0.0, _height.valueAt(now)),
      ),
    );
    if (_set) return body;
    // Melting where it was, on a size of its own: it draws in to a drop
    // however the body is spreading, or condensing somewhere else.
    return Rect.fromCenter(
      center: _ringHome,
      width: math.max(0.0, _meltWidth.valueAt(now)),
      height: math.max(0.0, _meltHeight.valueAt(now)),
    );
  }

  Rect? _litAt(double now) {
    if (!_litShown) return null;
    if (!_moving) return _cell;
    return Rect.fromLTRB(
      _left.valueAt(now),
      _top.valueAt(now),
      _right.valueAt(now),
      _bottom.valueAt(now),
    );
  }

  /// Everything that shows the choice at [now].
  ChoiceFrame frameAt(double now) {
    final cell = _cell;
    if (!_moving) {
      return cell == null
          ? const ChoiceFrame()
          : ChoiceFrame(ring: cell, ringStrength: 1, lit: cell);
    }
    final head = Offset(_headX.valueAt(now), _headY.valueAt(now));
    final tail = Offset(_tailX.valueAt(now), _tailY.valueAt(now));
    final w = math.max(0.0, _width.valueAt(now));
    final h = math.max(0.0, _height.valueAt(now));
    final body = Rect.fromCenter(center: head, width: w, height: h);
    final gap = (head - tail).distance;
    final radius = _radiusNow.valueAt(now);
    // What the body trails shrinks with the body, so a drop drawing in on its
    // way takes its neck in with it rather than leaving the neck behind.
    final scale = (math.max(w, h) / (2 * radius)).clamp(0.0, 1.0);
    final joined = gap < 1 || scale <= 0;
    final goo = CellGoo(
      body: body,
      corner: math.max(0.0, _corner.valueAt(now)),
      tail: tail,
      tailRadius: joined
          ? 0
          : radius * (0.8 - 0.3 * (gap / 160).clamp(0.0, 1.0)) * scale,
      neck: joined
          ? 0
          : (kCellGooNeckVolume / gap).clamp(
                  kCellGooNeckMin,
                  math.max(kCellGooNeckMin, radius * 0.7),
                ) *
                scale,
      velocity: Offset(_headX.velocityAt(now), _headY.velocityAt(now)),
    );
    final strength = _ring.valueAt(now).clamp(0.0, 1.0);
    final ring = strength > 0 ? _ringAt(now) : null;
    final lit = _litAt(now);
    var edgeSpeed = 0.0;
    for (final edge in <SpringValue>[_left, _top, _right, _bottom]) {
      edgeSpeed = math.max(edgeSpeed, edge.velocityAt(now).abs());
    }
    return ChoiceFrame(
      goo: goo,
      fill: _fill.valueAt(now).clamp(0.0, 1.0),
      ring: ring,
      ringStrength: strength,
      lit: lit,
      litRound: kGridLitRound * (edgeSpeed / 240).clamp(0.0, 1.0),
      litStrength: _litStrength.valueAt(now).clamp(0.0, 1.0),
    );
  }
}
