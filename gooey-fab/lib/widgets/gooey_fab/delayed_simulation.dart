import 'package:flutter/physics.dart';

/// Holds [startValue] for [delay], then runs [inner] as if it had begun then.
///
/// Mirrors `withDelay(ms, withSpring(...))`: the value is pinned while the
/// delay runs, so the spring starts from where it was left.
class DelayedSimulation extends Simulation {
  DelayedSimulation({required this.inner, required this.delay, required this.startValue});

  final Simulation inner;

  /// Seconds to wait before [inner] takes over.
  final double delay;

  final double startValue;

  @override
  double x(double time) => time < delay ? startValue : inner.x(time - delay);

  @override
  double dx(double time) => time < delay ? 0 : inner.dx(time - delay);

  @override
  bool isDone(double time) => time >= delay && inner.isDone(time - delay);
}
