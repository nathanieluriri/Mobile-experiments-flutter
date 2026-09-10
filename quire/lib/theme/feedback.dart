import 'package:flutter/services.dart';

/// The whole vocabulary of touch this app has.
///
/// Three feelings and a silence, rather than the five impact strengths the
/// platform offers, because the point of a haptic is that a reader can tell
/// what happened without looking, and five grades of buzz are five grades
/// nobody can tell apart. Everything that can be pressed shares [Feel.tap].
/// Only paper moving and the desk changing feel like anything else.
enum Feel {
  /// Something that presses but decides nothing, so it says nothing: a scrim
  /// swallowing a tap, a control that is only acknowledging the finger.
  none,

  /// Any ordinary control. The lightest mark the platform makes.
  tap,

  /// Paper moving: a page turned, a dog ear caught, a drawer settling open.
  turn,

  /// The desk changing: a document removed, or brought back.
  commit;

  /// Rings the phone.
  ///
  /// Safe on every platform and every device: the engine drops a request a
  /// device cannot honour rather than throwing, so this never needs guarding
  /// at a call site.
  void ring() {
    switch (this) {
      case Feel.none:
        return;
      case Feel.tap:
        HapticFeedback.selectionClick();
      case Feel.turn:
        HapticFeedback.lightImpact();
      case Feel.commit:
        HapticFeedback.mediumImpact();
    }
  }
}
