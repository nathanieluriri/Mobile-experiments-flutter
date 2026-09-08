import 'dart:math' as math;

import '../../theme/metrics.dart';

/// Height of one slot in the marquee. Thumbnails are shorter than this, so the
/// difference is the gap between them, and it fits an 84 x 108 thumbnail plus
/// its folio.
const kMarqueeItemHeight = kRiffleSlotHeight;

/// How far past each end of a finite marquee the list is padded, in viewports.
/// Without it the first and last item could never reach the centre.
const kFinitePaddingViewports = 1.5;

/// How far a thumbnail leans on its own, in degrees, either side of zero.
const kItemTiltRange = 2.5;

/// One tilt per item, drawn once from `Random(42)`.
///
/// The stack is meant to look hand stacked rather than machined, and a seeded
/// list built with the items is byte identical every run, which a per frame
/// jitter never could be.
List<double> marqueeTilts(int count, {int seed = 42}) {
  final random = math.Random(seed);
  return List<double>.generate(
    count,
    (_) => (random.nextDouble() * 2 - 1) * kItemTiltRange,
    growable: false,
  );
}
