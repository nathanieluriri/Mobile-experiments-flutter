import 'package:flutter/painting.dart';

import 'colors.dart';

/// Text styles the app draws with.
///
/// [base] deliberately leaves line height and letter spacing unset so text
/// takes its metrics straight from the font, the way an unstyled platform label
/// would. Wrap a screen in a `DefaultTextStyle` carrying it so no ambient
/// theme height leaks into the layout.
abstract final class AppTypography {
  static const fontFamily = 'Inter';

  static const base = TextStyle(fontFamily: fontFamily, color: AppColors.ink);

  static const screenTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const chatName = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.ink,
  );

  static const chatTime = TextStyle(fontSize: 13, color: AppColors.subtle);

  static const chatMessage = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.subtle,
  );
}
