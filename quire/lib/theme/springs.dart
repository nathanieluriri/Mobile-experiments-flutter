import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'metrics.dart';

/// Every spring in the app. There is no `Curves.elasticOut` anywhere: bounce
/// reads as toy, and these do the work.
abstract final class AppSprings {
  /// A released fold returning to its rest inset. Clamped by its caller, so it
  /// stops the instant it first reaches rest.
  static const peelSnap =
      SpringDescription(mass: 1, stiffness: 260, damping: 22);

  /// A dock button growing under the drag point, and shrinking back.
  static const dockScale =
      SpringDescription(mass: 1, stiffness: 260, damping: 20);

  /// The desk closing the gap a removed card leaves.
  static const shelfLayout =
      SpringDescription(mass: 1, stiffness: 200, damping: 30);

  /// A flip completing, and the reader sliding off on a back drag.
  static const pageSettle =
      SpringDescription(mass: 1, stiffness: 180, damping: 26);

  /// The cell bar rising from the sheet's bottom edge.
  static const valueBarSpring =
      SpringDescription(mass: 1, stiffness: 240, damping: 28);

  /// The navigation drawer coming in and going out, and with it the hamburger
  /// morphing into an arrow. One spring drives both, so the glyph is a readout
  /// of where the panel is rather than an animation of its own that happens to
  /// finish at about the same moment.
  static const drawer =
      SpringDescription(mass: 1, stiffness: 210, damping: 24);

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
  })  : _simulation = SpringSimulation(spring, 0, 1, 0),
        _clampSeconds =
            clampOvershoot ? _firstOvershootSeconds(spring) : double.infinity;

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
