import 'package:flutter/painting.dart';

import 'colors.dart';

/// The bundled font family.
const String kFontFamily = 'Inter';

/// Builds a text style in the app font.
///
/// [lineHeight] is an absolute line height in logical pixels. [tracking] is
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
    fontFamily: kFontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: lineHeight == null ? null : lineHeight / size,
    letterSpacing: tracking == 0 ? null : size * tracking,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    decoration: TextDecoration.none,
  );
}

/// Letter spacing used by uppercase eyebrow labels.
const double kTrackingWide = 0.025;
