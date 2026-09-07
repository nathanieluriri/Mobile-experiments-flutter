import 'package:flutter/widgets.dart';

/// The single family the app ships, at the four weights declared in pubspec.
const kFontFamily = 'Quicksand';

/// Quicksand's own line height: an ascender of 1.0 em over a descender of
/// 0.25 em, with no line gap. Text engines that fall back to the wider Windows
/// metrics would otherwise lay every unstyled line out 19 percent taller, so
/// every style states it.
const kLineHeight = 1.25;

abstract final class FontWeights {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semiBold = FontWeight.w600;
  static const bold = FontWeight.w700;
}
