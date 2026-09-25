import 'package:flutter/physics.dart';

/// Runs [carry] for [delay], then hands over to a simulation [build] makes from
/// the value and velocity reached at that moment.
///
/// Whatever was already in flight keeps going through the delay, and the new
/// spring inherits its momentum instead of restarting from a standstill. With
/// no [carry] the value simply holds at [hold], which is what happens on a
/// first tap.
class DelayedSimulation extends Simulation {
  DelayedSimulation({
    required this.delay,
    required this.hold,
    required this.build,
    this.carry,
  });

  /// Seconds before the handover.
  final double delay;

  /// Value held through the delay when nothing is in flight.
  final double hold;

  final Simulation Function(double value, double velocity) build;

  /// The animation the delay lets finish, in a time base starting at zero.
  final Simulation? carry;

  Simulation? _handover;

  Simulation get _next =>
      _handover ??= build(carry?.x(delay) ?? hold, carry?.dx(delay) ?? 0);

  @override
  double x(double time) =>
      time < delay ? (carry?.x(time) ?? hold) : _next.x(time - delay);

  @override
  double dx(double time) =>
      time < delay ? (carry?.dx(time) ?? 0) : _next.dx(time - delay);

  @override
  bool isDone(double time) => time >= delay && _next.isDone(time - delay);
}
