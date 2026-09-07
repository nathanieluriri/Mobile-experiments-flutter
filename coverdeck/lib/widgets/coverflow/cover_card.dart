import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../data/albums.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import 'coverflow_constants.dart';
import 'reflection.dart';

/// One cover in the deck, tilted and scaled by its distance from the focus.
///
/// The transform is built in the same order the deck applies it: the
/// perspective, then the sideways travel, then the tilt, then the scale, all
/// about the centre of the cover and its reflection together.
class CoverCard extends StatelessWidget {
  const CoverCard({
    super.key,
    required this.album,
    required this.index,
    required this.scrollX,
    required this.size,
    required this.spacing,
    required this.centerGap,
    required this.containerWidth,
  });

  final Album album;
  final int index;
  final double scrollX;
  final double size;
  final double spacing;
  final double centerGap;
  final double containerWidth;

  /// Distance of this cover from the focus, in covers.
  double get distance => index - scrollX;

  /// Sideways travel in points. The tanh term eases in the extra centre gap so
  /// the focused cover separates from the stack without a jump at the crossover.
  double get travel => distance * spacing + tanh(distance * 1.6) * centerGap;

  /// Tilt in degrees, flat at the focus and clamped one cover out.
  double get tiltDegrees => interpolate(
    distance,
    const [-1, 0, 1],
    const [maxTiltDeg, 0, -maxTiltDeg],
  );

  /// Scale, full at the focus and easing on past the first neighbour.
  double get scale => interpolate(
    distance.abs(),
    const [0, 1, 4],
    const [1, sideScale, sideScale * 0.94],
  );

  /// Opacity, gone five and a half covers out.
  double get opacity => interpolate(
    distance.abs(),
    const [0, 1, 4.5, 5.5],
    const [1, 0.92, 0.6, 0],
  );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: containerWidth / 2 - size / 2,
      top: 0,
      width: size,
      child: Opacity(
        opacity: opacity,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, -1 / perspective)
            ..translateByDouble(travel, 0, 0, 1)
            ..rotateY(tiltDegrees * math.pi / 180)
            ..scaleByDouble(scale, scale, scale, 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(asset: album.imageAsset, size: size),
              const SizedBox(height: reflectionGap),
              Reflection(
                asset: album.imageAsset,
                size: size,
                height: size * reflectionRatio,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.asset, required this.size});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(coverRadius));
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: AppColors.coverBorder,
          width: hairlineWidth(context),
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover),
      ),
    );
  }
}
