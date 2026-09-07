import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/colors.dart';

/// A soft band of light that sweeps across whatever clips it. [progress] runs
/// 0 to 1; the band starts just off the left edge and ends just past the right,
/// fading in over the first tenth and out over the last.
class Shimmer extends StatelessWidget {
  const Shimmer({
    super.key,
    required this.progress,
    required this.width,
    required this.height,
    required this.band,
    required this.opacity,
    required this.skew,
    this.color = AppColors.white,
  });

  /// 0 to 1 across one sweep.
  final double progress;

  /// How far the band travels: the width of the surface it crosses.
  final double width;

  /// How tall the band is drawn. It is placed from `-height` to `2 * height`
  /// so a skewed band still covers the surface at both ends.
  final double height;

  final double band;
  final double opacity;

  /// Lean of the band in degrees, leading edge to the right.
  final double skew;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final travel = -band + (width + band * 2) * progress;
    return Positioned(
      left: travel,
      top: -height,
      width: band,
      height: height * 3,
      child: IgnorePointer(
        child: Opacity(
          opacity: _fade(progress),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-skew * math.pi / 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0),
                    color.withValues(alpha: opacity),
                    color.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _fade(double progress) {
    if (progress <= 0 || progress >= 1) {
      return 0;
    }
    if (progress < 0.12) {
      return progress / 0.12;
    }
    if (progress > 0.88) {
      return (1 - progress) / 0.12;
    }
    return 1;
  }
}
