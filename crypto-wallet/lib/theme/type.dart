import 'package:flutter/painting.dart';

import 'colors.dart';

/// The bundled font family.
const String kFontFamily = 'Inter';

/// Builds a text style in the app font.
///
/// The style does not inherit the ambient Material text style, so no default
/// line height or letter spacing leaks in: glyphs sit at their natural
/// metrics unless [lineHeight] is given. [lineHeight] is an absolute line
/// height in logical pixels, with the glyphs centred in it. [tracking] is
/// letter spacing as a fraction of the font size.
TextStyle text(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AppColors.ink,
  double? lineHeight,
  double tracking = 0,
  bool tabular = false,
}) {
  return TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: lineHeight == null ? null : lineHeight / size,
    leadingDistribution: lineHeight == null ? null : TextLeadingDistribution.even,
    letterSpacing: tracking == 0 ? 0 : size * tracking,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    decoration: TextDecoration.none,
  );
}

/// Letter spacing used by uppercase eyebrow labels.
const double kTrackingWide = 0.025;
