import 'dart:ui';

/// Colours that mean the same thing whatever the device is set to: the brand
/// marks and the accent each step is built around.
abstract final class AppColors {
  static const white = Color(0xFFFFFFFF);

  /// Near black. What the flow is written in on white, and what its call to
  /// action is written in on black.
  static const ink = Color(0xFF0D0D0D);

  /// True black. The ground on a dark device, chosen so that even the darkest
  /// cards, at 101010 and 161616, still sit above it.
  static const pitch = Color(0xFF000000);

  /// Near white. The other end of that pair.
  static const paper = Color(0xFFF2F2F2);

  /// Secondary text. Legible on both grounds, so it does not change.
  static const muted = Color(0xFF8E8E93);

  static const spotify = Color(0xFF1ED760);
  static const locationAccent = Color(0xFF4DA3FF);
  static const locationDisc = Color(0xFF0A84FF);
}
