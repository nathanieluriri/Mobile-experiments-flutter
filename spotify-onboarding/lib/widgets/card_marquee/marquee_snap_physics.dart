import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'marquee_constants.dart';

/// Scrolling that slows down quickly and comes to rest on a slot boundary.
class MarqueeSnapPhysics extends ScrollPhysics {
  const MarqueeSnapPhysics({super.parent});

  /// Friction per second equivalent to losing one percent of the remaining
  /// speed every millisecond, which is the fast deceleration rate.
  static const _drag = 4.3171e-5;

  @override
  MarqueeSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return MarqueeSnapPhysics(parent: buildParent(ancestor));
  }

  /// Where a flick of [velocity] would come to rest, rounded to the nearest
  /// slot and kept inside the scrollable.
  double restingPoint(ScrollMetrics position, double velocity) {
    final coasted = velocity == 0
        ? position.pixels
        : FrictionSimulation(_drag, position.pixels, velocity).finalX;
    final snapped =
        (coasted / kMarqueeItemHeight).roundToDouble() * kMarqueeItemHeight;
    return snapped.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = restingPoint(position, velocity);
    if ((target - position.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}
