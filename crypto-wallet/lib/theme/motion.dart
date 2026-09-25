import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Spring presets shared by every interaction.
abstract final class Springs {
  static const press = SpringDescription(
    mass: 0.7,
    stiffness: 420,
    damping: 22,
  );
  static const roll = SpringDescription(mass: 0.8, stiffness: 260, damping: 20);
  static const pop = SpringDescription(mass: 0.8, stiffness: 300, damping: 14);
  static const sheet = SpringDescription(
    mass: 0.9,
    stiffness: 300,
    damping: 28,
  );
  static const screen = SpringDescription(mass: 1, stiffness: 280, damping: 30);
  static const layout = SpringDescription(
    mass: 0.8,
    stiffness: 340,
    damping: 26,
  );
}

/// Easing curves used by timed animations.
abstract final class Eases {
  static const ios = Cubic(0.25, 0.1, 0.25, 1);
  static const iosOut = Curves.easeOutCubic;
  static const iosInOut = Cubic(0.42, 0, 0.58, 1);
}

/// Builds a spring simulation that moves [from] to [to].
SpringSimulation springTo(
  SpringDescription spring,
  double from,
  double to, {
  double velocity = 0,
}) {
  return SpringSimulation(spring, from, to, velocity);
}

/// A curve that follows a spring from 0 to 1 over [duration], so timed
/// transitions (routes, switchers) can carry the spring's shape.
class SpringCurve extends Curve {
  SpringCurve(this.spring)
    : _simulation = SpringSimulation(spring, 0, 1, 0),
      duration = _settleDuration(spring);

  final SpringDescription spring;
  final SpringSimulation _simulation;

  /// How long the spring takes to come to rest.
  final Duration duration;

  static Duration _settleDuration(SpringDescription spring) {
    final simulation = SpringSimulation(spring, 0, 1, 0);
    var t = 0.0;
    while (!simulation.isDone(t) && t < 10) {
      t += 0.001;
    }
    return Duration(microseconds: (t * 1e6).round());
  }

  @override
  double transformInternal(double t) {
    return _simulation.x(t * duration.inMicroseconds / 1e6);
  }

  /// Drives [parent] through this spring.
  ///
  /// Running in reverse starts a fresh spring that settles from 1 back to 0,
  /// the way releasing a value to its resting position does, instead of
  /// replaying the forward curve backwards in time (which would hold still
  /// while the spring's long tail unwinds and then rush the last stretch).
  /// The caller owns the returned animation and must dispose it.
  CurvedAnimation drive(Animation<double> parent) {
    return CurvedAnimation(parent: parent, curve: this, reverseCurve: flipped);
  }
}
