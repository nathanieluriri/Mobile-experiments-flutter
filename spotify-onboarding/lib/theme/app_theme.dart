import 'package:flutter/material.dart';

import 'palette.dart';
import 'typography.dart';

/// The flow's theme for one ground. The app hands Flutter both and lets the
/// device choose.
ThemeData appTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  return ThemeData(
    brightness: brightness,
    fontFamily: kFontFamily,
    scaffoldBackgroundColor: palette.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1ED760),
      brightness: brightness,
      surface: palette.background,
    ),
  );
}
