import 'package:flutter/painting.dart';

import 'colors.dart';

/// Font family bundled with the app.
const kFontFamily = 'Inter';

/// The type scale.
///
/// Every style is complete rather than inherited, so no ambient text style can
/// change a size, a weight, or the spacing between letters. Line heights are
/// multipliers of the font size, and the extra leading is split evenly above
/// and below the glyphs, which is how the design's line heights are measured.
abstract final class AppText {
  static const headline = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 34,
    height: 38 / 34,
    letterSpacing: -1,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const cardTitle = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 23,
    height: 25 / 23,
    letterSpacing: -0.5,
    fontWeight: FontWeight.w700,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const body = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 13,
    height: 19 / 13,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const label = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static const labelMuted = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.muted,
  );

  static const button = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const caption = TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.pillLabel,
  );
}
