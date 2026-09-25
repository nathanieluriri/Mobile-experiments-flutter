import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../theme/springs.dart';

/// How far a fling carries the deck, in seconds of travel at release speed.
const flingProjection = 0.18;

/// Position of the deck, measured in covers, plus the spring that settles it.
///
/// Dragging sets the position directly; releasing, tapping a side cover and
/// skipping all hand off to [snapSpring].
class CoverflowController extends ChangeNotifier {
  CoverflowController({
    required TickerProvider vsync,
    required this.count,
    int initialIndex = 0,
  }) : _index = initialIndex,
       _position = AnimationController.unbounded(
         vsync: vsync,
         value: initialIndex.toDouble(),
       ) {
    _position.addListener(_handlePositionChange);
  }

  /// Number of covers in the deck.
  final int count;

  /// Called when the focused cover changes, never on the first build.
  ValueChanged<int>? onIndexChanged;

  final AnimationController _position;
  int _index;

  /// Position of the deck in covers, which is fractional while it moves.
  double get scrollX => _position.value;

  /// Index of the focused cover.
  int get index => _index;

  /// Lowest position a drag may reach, a third of a cover past the first one.
  double get minScrollX => -0.35;

  /// Highest position a drag may reach.
  double get maxScrollX => count - 0.65;

  void _handlePositionChange() {
    final next = clampDouble(scrollX, 0, count - 1).round();
    if (next != _index) {
      _index = next;
      onIndexChanged?.call(next);
    }
    notifyListeners();
  }

  /// Places the deck at [value], stopping any spring in flight.
  void dragTo(double value) {
    _position
      ..stop()
      ..value = clampDouble(value, minScrollX, maxScrollX);
  }

  /// Settles onto [target] carrying [velocity] in covers per second.
  void springTo(int target, {double velocity = 0}) {
    _position.animateWith(
      SpringSimulation(
        snapSpring,
        scrollX,
        clampDouble(target.toDouble(), 0, count - 1),
        velocity,
      ),
    );
  }

  /// Cover a release at [velocity] covers per second lands on.
  int projectedTarget(double velocity) {
    return clampDouble(
      (scrollX + velocity * flingProjection).roundToDouble(),
      0,
      count - 1,
    ).round();
  }

  /// Settles onto the cover a release at [velocity] covers per second reaches.
  void fling(double velocity) =>
      springTo(projectedTarget(velocity), velocity: velocity);

  /// Settles onto [index], clamped into the deck.
  void scrollTo(int index) =>
      springTo(clampDouble(index.toDouble(), 0, count - 1).round());

  @override
  void dispose() {
    _position
      ..removeListener(_handlePositionChange)
      ..dispose();
    super.dispose();
  }
}
