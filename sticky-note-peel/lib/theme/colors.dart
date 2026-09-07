import 'dart:ui';

/// The app palette.
abstract final class AppColors {
  static const ink = Color(0xFF232837);
  static const surface = Color(0xFF353B4F);
  static const noteText = Color(0xFF31374F);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const dockLabel = Color(0xFFE8EAF2);
  static const danger = Color(0xFFF26D6D);
  static const info = Color(0xFF4BA3F5);
  static const success = Color(0xFF3DBB7E);
}

/// Scales every channel of [color] by `1 + amount`, clamped to a byte.
/// A negative amount darkens; the fold flap uses -0.2.
Color shade(Color color, double amount) {
  int channel(double component) =>
      (component * (1 + amount)).round().clamp(0, 255);
  return Color.fromARGB(
    (color.a * 255).round(),
    channel(color.r * 255),
    channel(color.g * 255),
    channel(color.b * 255),
  );
}
