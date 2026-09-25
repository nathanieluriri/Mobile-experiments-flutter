import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/metrics.dart';
import 'marquee_constants.dart';

/// Places one thumbnail in its slot and leans it around the arc.
///
/// The further a slot sits from the middle of the viewport, the more it leans,
/// the further left it slides, and the smaller it is drawn. That
/// foreshortening is what your eye does looking down the edge of a fanned page
/// block, which is why the marquee reads as riffling a book rather than as a
/// list.
class MarqueeArcItem extends StatelessWidget {
  const MarqueeArcItem({
    super.key,
    required this.slot,
    required this.controller,
    required this.viewportHeight,
    required this.itemTilt,
    required this.child,
    this.leadingPadding = 0,
  });

  /// Index of this thumbnail's slot.
  final int slot;

  /// Drives the arc: every scroll changes where this slot sits.
  final ScrollController controller;

  /// Height of the marquee's viewport.
  final double viewportHeight;

  /// This item's own lean, in degrees.
  final double itemTilt;

  /// How far the list is padded before slot zero, in a finite marquee.
  final double leadingPadding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMarqueeItemHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final offset = controller.hasClients
              ? controller.offset
              : controller.initialScrollOffset;
          return Transform(
            transform: arcTransform(
              slot: slot,
              scrollOffset: offset - leadingPadding,
              viewportHeight: viewportHeight,
              itemTilt: itemTilt,
            ),
            alignment: Alignment.center,
            child: child,
          );
        },
        child: Center(child: child),
      ),
    );
  }
}

/// The lean, slide, and shrink applied to the thumbnail in [slot].
Matrix4 arcTransform({
  required int slot,
  required double scrollOffset,
  required double viewportHeight,
  required double itemTilt,
}) {
  if (viewportHeight <= 0) {
    return Matrix4.identity();
  }
  final half = viewportHeight / 2;
  final centreOffset =
      slot * kMarqueeItemHeight + kMarqueeItemHeight / 2 - scrollOffset - half;
  final centreDistance = centreOffset / half;
  final clamped = centreDistance.clamp(
    -kCenterDistanceClamp,
    kCenterDistanceClamp,
  );
  final tilt = centreDistance * kMaxTiltDeg + itemTilt * kItemTiltInfluence;
  final radians = tilt * math.pi / 180;
  final slide = -kArcRadius * (1 - math.cos(radians));
  final scale = 1 - clamped.abs() * kMaxScaleShrink;
  final c = math.cos(radians) * scale;
  final s = math.sin(radians) * scale;
  // Columns of translate(slide) * rotate(tilt) * scale(scale).
  return Matrix4(c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, slide, 0, 0, 1);
}
