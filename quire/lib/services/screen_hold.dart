import 'package:flutter/services.dart';

/// The channel the platform holds the screen awake on.
const String kScreenChannel = 'ng.com.uriri.quire/screen';

/// What this asks the platform for.
const String kScreenHold = 'hold';

/// Keeps the screen on while something is being watched rather than touched.
///
/// A presentation is a stretch of minutes with no touches in it, which is
/// exactly what a phone reads as nobody being there. Left alone, the screen
/// dims and then locks part way through a slide, in front of whoever is
/// watching, and the only way out is to unlock the phone and find the place
/// again. Nothing else in quire needs this: reading a page involves a hand.
///
/// A platform that does not answer is a platform that does not sleep, or one
/// this app has not been taught about. Either way the presentation goes on:
/// a reader must never lose a slide because a channel was missing.
class ScreenHold {
  ScreenHold({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kScreenChannel);

  final MethodChannel _channel;

  bool _held = false;

  /// True while the screen is being held.
  bool get held => _held;

  Future<void> hold() => _set(true);

  Future<void> release() => _set(false);

  Future<void> _set(bool held) async {
    if (held == _held) return;
    _held = held;
    try {
      await _channel.invokeMethod<void>(kScreenHold, held);
    } on MissingPluginException {
      // Nothing to hold the screen with.
    } on PlatformException {
      // The window would not take the flag. Not worth a word to the reader.
    }
  }
}
