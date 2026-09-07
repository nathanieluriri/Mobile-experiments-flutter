import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/marquee_item.dart';
import '../marquee_card.dart';
import 'marquee_constants.dart';

/// Places one card in its slot and leans it around the arc.
///
/// The further a slot sits from the middle of the viewport, the more the card
/// leans, the further left it slides, and the smaller it is drawn.
class MarqueeArcItem extends StatelessWidget {
  const MarqueeArcItem({
    super.key,
    required this.item,
    required this.slot,
    required this.controller,
    required this.viewportHeight,
  });

  final MarqueeItem item;

  /// Index of this card's slot in the endless list.
  final int slot;

  /// Drives the arc: every scroll changes where this slot sits.
  final ScrollController controller;

  /// Height of the marquee's viewport.
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMarqueeItemHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return Transform(
            transform: arcTransform(
              slot: slot,
              scrollOffset: controller.hasClients
                  ? controller.offset
                  : controller.initialScrollOffset,
              viewportHeight: viewportHeight,
              itemTilt: item.tilt,
            ),
            alignment: Alignment.center,
            child: child,
          );
        },
        child: Center(child: MarqueeCard(item: item)),
      ),
    );
  }
}

/// The lean, slide, and shrink applied to the card in [slot].
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
