import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

abstract final class AppSprings {
  /// The fold point returning to its rest inset when a drag is released over
  /// nothing. Clamped, so it settles the moment it first reaches the target.
  static const snapBack =
      SpringDescription(mass: 1, stiffness: 260, damping: 22);

  /// A dock button growing under the drag point, and shrinking back.
  static const dockButtonScale =
      SpringDescription(mass: 1, stiffness: 260, damping: 20);

  /// The list closing the gap a removed note leaves behind.
  static const noteListLayout =
      SpringDescription(mass: 1, stiffness: 200, damping: 30);
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
