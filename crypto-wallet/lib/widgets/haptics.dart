import 'package:flutter/services.dart';

enum HapticKind { tap, press, selection, success, none }

/// Haptic feedback at the same trigger points as the design.
abstract final class Haptics {
  static void tap() => HapticFeedback.lightImpact();
  static void press() => HapticFeedback.mediumImpact();
  static void selection() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.heavyImpact();

  static void fire(HapticKind kind) {
    switch (kind) {
      case HapticKind.tap:
        tap();
      case HapticKind.press:
        press();
      case HapticKind.selection:
        selection();
      case HapticKind.success:
        success();
      case HapticKind.none:
        break;
    }
  }
}
