import 'package:flutter/painting.dart';

import 'colors.dart';

/// Core Animation takes a shadow radius as the gaussian sigma, while
/// [BoxShadow] takes a blur radius that Flutter converts with
/// `sigma = 0.57735 * blurRadius + 0.5`. This inverts that, so a sigma written
/// for the design produces the same softness here.
double blurForShadowRadius(double sigma) => (sigma - 0.5) / 0.57735;

/// Every shadow in the app, all tinted [AppColors.shadowInk]. Nothing outside
/// this class casts a shadow.
abstract final class AppShadows {
  /// A sheet lying on the desk: every card, the reading sheet, a thumbnail,
  /// the pad.
  static List<BoxShadow> leafRest() => [
        BoxShadow(
          color: AppColors.shadowInk.withValues(alpha: 0.08),
          blurRadius: blurForShadowRadius(10),
          offset: const Offset(0, 3),
        ),
      ];

  /// A sheet picked up: a peeled card, a dragged signature, the centre riffle
  /// slot. The alpha runs 0 to 0.18 across the lift, so it is a function.
  static List<BoxShadow> leafLift(double opacity) => [
        BoxShadow(
          color: AppColors.shadowInk.withValues(alpha: opacity),
          blurRadius: blurForShadowRadius(22),
          offset: const Offset(0, 12),
        ),
      ];

  /// Floating chrome: header buttons, the folio chip, dock buttons.
  static List<BoxShadow> dock() => [
        BoxShadow(
          color: AppColors.shadowInk.withValues(alpha: 0.20),
          blurRadius: blurForShadowRadius(14),
          offset: const Offset(0, 6),
        ),
      ];

  /// The cell bar rising from the sheet's bottom edge, so its shadow is thrown
  /// upward.
  static List<BoxShadow> valueBar() => [
        BoxShadow(
          color: AppColors.shadowInk.withValues(alpha: 0.22),
          blurRadius: blurForShadowRadius(30),
          offset: const Offset(0, -8),
        ),
      ];

  /// What [leafRest] becomes under a finger.
  static List<BoxShadow> pressed() => [
        BoxShadow(
          color: AppColors.shadowInk.withValues(alpha: 0.06),
          blurRadius: blurForShadowRadius(4),
          offset: const Offset(0, 1),
        ),
      ];

  /// The full alpha [leafLift] reaches.
  static const leafLiftAlpha = 0.18;
}
