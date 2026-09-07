import 'package:flutter/painting.dart';

/// The palette the app is built from.
abstract final class AppColors {
  static const canvas = Color(0xFFF2F2F6);
  static const ink = Color(0xFF17171B);
  static const inkSoft = Color(0xFF3A3A3C);
  static const sub = Color(0xFF97979E);
  static const subStrong = Color(0xFF6E6E73);
  static const faint = Color(0xFFBFBFC6);
  static const accent = Color(0xFF0A84FF);
  static const white = Color(0xFFFFFFFF);

  /// Sits behind artwork until the picture is decoded.
  static const artworkBackdrop = Color(0x73FFFFFF);

  /// Ink at 45 percent, used for the secondary line on tinted cards.
  static const inkMuted = Color(0x7317171B);

  /// Hairlines and the pill handle.
  static const hairline = Color(0x0D000000);
  static const handle = Color(0x26000000);
}
