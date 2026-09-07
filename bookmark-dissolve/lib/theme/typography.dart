import 'package:flutter/painting.dart';

/// The only font family in the app.
const kFontFamily = 'Inter';

/// A text style whose extra line height is split evenly above and below the
/// glyphs, the way a line box behaves on the web and on iOS.
TextStyle text({
  required double size,
  double? lineHeight,
  FontWeight? weight,
  Color? color,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: kFontFamily,
    fontSize: size,
    height: lineHeight == null ? null : lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
