import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'metrics.dart';

/// Every spring in the app. There is no `Curves.elasticOut` anywhere: bounce
/// reads as toy, and these do the work.
abstract final class AppSprings {
  /// A released fold returning to its rest inset. Clamped by its caller, so it
  /// stops the instant it first reaches rest.
  static const peelSnap = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );

  /// A dock button growing under the drag point, and shrinking back.
  static const dockScale = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 20,
  );

  /// The desk closing the gap a removed card leaves.
  static const shelfLayout = SpringDescription(
    mass: 1,
    stiffness: 200,
    damping: 30,
  );

  /// A flip completing, and the reader sliding off on a back drag.
  static const pageSettle = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 26,
  );

  /// The body of goo carrying the choice of cell across a sheet: quick to
  /// go, with a little give as it gets there.
  static final gooHead = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 110,
    ratio: 0.88,
  );

  /// What the body leaves behind as it goes. Slower than the body, so it is
  /// drawn out into a neck and then pulled in after it.
  static final gooTail = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 46,
    ratio: 1,
  );

  /// The body gathering into a drop and spreading into a cell, going a little
  /// past the cell's edges and settling back, the way something thick does.
  static final gooSpread = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 150,
    ratio: 0.72,
  );

  /// The goo coming up as a choice sets off, and the ring drawing into it.
  static final gooRise = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 180,
    ratio: 1,
  );

  /// The ring coming out of the goo once it has spread, and the goo giving
  /// way to the ring. Slow, so the ring is seen to form rather than to switch
  /// on.
  static final gooSet = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 80,
    ratio: 1,
  );

  /// The goo giving way to the ring that has formed round it.
  static final gooGiveWay = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 120,
    ratio: 1,
  );

  /// The lit letter and number: the edge on the side the choice is going,
  /// and the edge that follows it in. Neither goes past where it is going,
  /// so a letter is never lit and unlit and lit again.
  static final litLead = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 120,
    ratio: 1,
  );
  static final litTrail = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 60,
    ratio: 1,
  );

  /// The grid gliding to a cell it has been asked to show. Stopped dead, so
  /// it never runs past the row it was sent to, and soft enough that a
  /// stream of requests is followed rather than chased.
  static final reveal = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 110,
    ratio: 1,
  );

  /// The cell bar rising, going back down, and opening or closing the room
  /// for a comment. None of them goes past where it is going, because the
  /// bar is held inside its own slot and a spring cut off at the slot's edge
  /// would stop dead.
  static final barRise = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 90,
    ratio: 1,
  );
  static final barFall = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 140,
    ratio: 1,
  );
  static final barNote = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 110,
    ratio: 1,
  );

  /// The reader's band going as the reading moves on and coming back when it
  /// turns round, and whatever a body holds under the band going up and down
  /// with it, such as a grid's letters.
  ///
  /// A spring rather than a timed slide, because the band is sent back half
  /// way through leaving whenever a reader changes direction, and a spring
  /// sent back sets off from where it is at the speed it has. It never goes
  /// past where it is going: a band is held at the top of the screen, and a
  /// spring cut off there would stop dead.
  static final band = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 160,
    ratio: 1,
  );

  /// The navigation drawer coming in and going out, and with it the hamburger
  /// morphing into an arrow. One spring drives both, so the glyph is a readout
  /// of where the panel is rather than an animation of its own that happens to
  /// finish at about the same moment.
  static const drawer = SpringDescription(mass: 1, stiffness: 210, damping: 24);

  /// The drawer's damping, as a share of what would stop it dead.
  ///
  /// Taken off the spring rather than written down beside it, so anything
  /// built to move like the drawer keeps moving like the drawer if the drawer
  /// is ever retuned.
  static final drawerRatio =
      drawer.damping / (2 * math.sqrt(drawer.stiffness * drawer.mass));

  /// A document arriving from the edge of the screen: the drawer's shape, at a
  /// page's size.
  ///
  /// The panel crosses its own width and a page crosses the whole screen, so
  /// the same spring carries the page a good deal faster than it carries the
  /// panel, and a page that arrives that fast reads as a cut rather than as
  /// something being brought in.
  ///
  /// How fast a spring moves goes with the square root of its stiffness, so
  /// bringing the stiffness down by the square of the ratio between the two
  /// distances leaves the page travelling at the panel's speed instead of in
  /// the panel's time. The damping ratio is the panel's own, so the curve has
  /// exactly the panel's shape: a quarter of the way at a fifth of the time,
  /// six tenths at two fifths, and easing into place from there.
  static final documentArrival = SpringDescription.withDampingRatio(
    mass: drawer.mass,
    stiffness:
        drawer.stiffness *
        (drawerWidth(kScreenWidth) / kScreenWidth) *
        (drawerWidth(kScreenWidth) / kScreenWidth),
    ratio: drawerRatio,
  );
}

/// A number carried on a spring towards wherever it was last sent.
///
/// Sending it somewhere new while it is still moving sets off from where it
/// is, at the speed it has, which is what lets a motion be changed half way
/// through without a jump and without a stop. Time is whatever clock the
/// caller keeps, in seconds.
class SpringValue {
  SpringValue(double value, {this.tolerance = pointTolerance}) : _to = value;

  /// Close enough to stop, for something measured in points.
  static const pointTolerance = Tolerance(distance: 0.25, velocity: 2.5);

  /// Close enough to stop, for a share from nought to one.
  static const shareTolerance = Tolerance(distance: 0.004, velocity: 0.02);

  final Tolerance tolerance;

  SpringSimulation? _run;
  SpringDescription? _spring;
  double _began = 0;
  double _to;

  /// Where it was last sent.
  double get target => _to;

  double valueAt(double now) {
    final run = _run;
    return run == null ? _to : run.x(math.max(0, now - _began));
  }

  double velocityAt(double now) {
    final run = _run;
    if (run == null || run.isDone(math.max(0, now - _began))) return 0;
    return run.dx(math.max(0, now - _began));
  }

  bool restingAt(double now) {
    final run = _run;
    return run == null || run.isDone(math.max(0, now - _began));
  }

  /// Sets off for [target] on [spring] from wherever it is at [now].
  void sendTo(double target, double now, SpringDescription spring) {
    if (target == _to) return;
    _spring = spring;
    _run = SpringSimulation(
      spring,
      valueAt(now),
      target,
      velocityAt(now),
      tolerance: tolerance,
      snapToEnd: true,
    );
    _began = now;
    _to = target;
  }

  /// Puts it at [value] at once, at rest.
  void jumpTo(double value) {
    _run = null;
    _to = value;
  }

  /// Moves where it is and where it is going by [delta] together, keeping the
  /// motion exactly as it was: the same speed, the same distance still to go.
  /// For a value measured from something that has itself moved.
  void shiftBy(double delta, double now) {
    if (delta == 0) return;
    final run = _run;
    final spring = _spring;
    if (run == null || spring == null || restingAt(now)) {
      jumpTo(valueAt(now) + delta);
      return;
    }
    final at = valueAt(now) + delta;
    final speed = velocityAt(now);
    _to += delta;
    _run = SpringSimulation(
      spring,
      at,
      _to,
      speed,
      tolerance: tolerance,
      snapToEnd: true,
    );
    _began = now;
  }
}

/// Runs a [SpringDescription] from 0 to 1 as a [Curve] over [duration], so a
/// plain [AnimationController] reproduces the phone's spring exactly.
///
/// With [clampOvershoot] the curve holds at 1 from the first moment it reaches
/// it, matching `overshootClamping` on the phone.
class SpringCurve extends Curve {
  SpringCurve(
    SpringDescription spring, {
    required this.duration,
    bool clampOvershoot = false,
  }) : _simulation = SpringSimulation(spring, 0, 1, 0),
       _clampSeconds = clampOvershoot
           ? _firstOvershootSeconds(spring)
           : double.infinity;

  final Duration duration;
  final SpringSimulation _simulation;
  final double _clampSeconds;

  @override
  double transformInternal(double t) {
    final seconds = t * duration.inMicroseconds / 1e6;
    if (seconds >= _clampSeconds) {
      return 1;
    }
    return _simulation.x(seconds);
  }
}

/// The first moment a spring released from 0 reaches 1, or infinity if it never
/// overshoots within the search window.
double _firstOvershootSeconds(SpringDescription spring) {
  final simulation = SpringSimulation(spring, 0, 1, 0);
  for (var ms = 1; ms <= _searchMs; ms++) {
    if (simulation.x(ms / 1000) >= 1) {
      return ms / 1000;
    }
  }
  return double.infinity;
}

const _searchMs = 4000;

/// How long a spring needs to settle, rounded up to whole milliseconds. Used as
/// the duration of the controller driving a [SpringCurve] so the curve always
/// finishes at 1. With [clampOvershoot] this is the first overshoot instead.
Duration springDuration(
  SpringDescription spring, {
  bool clampOvershoot = false,
}) {
  if (clampOvershoot) {
    final seconds = _firstOvershootSeconds(spring);
    if (seconds.isFinite) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
  }
  final simulation = SpringSimulation(spring, 0, 1, 0);
  for (var ms = 1; ms <= _searchMs; ms++) {
    if (simulation.isDone(ms / 1000)) {
      return Duration(milliseconds: ms);
    }
  }
  return const Duration(milliseconds: _searchMs);
}
