import 'package:flutter/painting.dart';

import 'colors.dart';

/// The only font family in the app.
const kFontFamily = 'Inter';

/// A text style built only from the values given here.
///
/// It does not inherit, so no ambient style can add tracking or stretch the
/// line box: a string is set exactly as its size, weight and line height say.
/// Extra line height is split evenly above and below the glyphs, the way a
/// line box behaves on the web and on iOS.
TextStyle text({
  required double size,
  double? lineHeight,
  FontWeight? weight,
  Color color = AppColors.ink,
  double? letterSpacing,
}) {
  return TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: size,
    height: lineHeight == null ? null : lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
