import 'package:flutter/painting.dart';

import 'colors.dart';

/// Core Animation takes a shadow radius as the gaussian sigma, while
/// [BoxShadow] takes a blur radius that Flutter converts with
/// `sigma = 0.57735 * blurRadius + 0.5`. This inverts that so a radius written
/// for the phone produces the same softness here.
double blurForShadowRadius(double sigma) => (sigma - 0.5) / 0.57735;

abstract final class AppShadows {
  static List<BoxShadow> composeButton() => [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.35),
      blurRadius: blurForShadowRadius(16),
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> dockButton() => [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.3),
      blurRadius: blurForShadowRadius(12),
      offset: const Offset(0, 6),
    ),
  ];

  /// The lifted note's shadow fades in with the lift, so its opacity is a
  /// parameter rather than a constant.
  static List<BoxShadow> liftedNote(double opacity) => [
    BoxShadow(
      color: AppColors.black.withValues(alpha: opacity),
      blurRadius: blurForShadowRadius(24),
      offset: const Offset(0, 16),
    ),
  ];
}
