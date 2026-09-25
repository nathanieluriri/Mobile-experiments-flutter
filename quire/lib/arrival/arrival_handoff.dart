import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The channel the platform's own splash is handed over on.
const kArrivalChannel = 'ng.com.uriri.quire/arrival';

/// The entrypoint argument Android passes when it owns the splash and will
/// report it and take it away itself.
const kArrivalHandsOver = 'handsOver';

/// What the platform's splash showed, as it measured it, in logical pixels of
/// the Flutter view.
class SplashReport {
  const SplashReport({
    this.markInk,
    this.nameBox,
    this.showedMark = true,
    this.showedName = true,
    this.markPixels,
    this.markPixelsRect,
    this.namePixels,
  });

  /// The rect the mark's ink covered, or null if it could not be measured.
  final Rect? markInk;

  /// The name's slot, or null if it could not be found.
  final Rect? nameBox;

  /// False when the platform put up its splash without the mark, which it
  /// does for some launches from other apps.
  final bool showedMark;

  /// False when the splash left the name off, which Android does on a screen
  /// too short to fit it under the mark.
  final bool showedName;

  /// The splash's mark exactly as it was on the screen, and the rect it was
  /// drawn in. Android 12 draws it from a small bitmap scaled up, a shade
  /// softer than the vector, so the first frame shows these pixels rather
  /// than sharpen in front of the reader.
  final ui.Image? markPixels;
  final Rect? markPixelsRect;

  /// The splash's name exactly as it was on the screen, drawn in [nameBox].
  final ui.Image? namePixels;

  void dispose() {
    markPixels?.dispose();
    namePixels?.dispose();
  }
}

/// The Flutter side of the handover.
///
/// On Android 12 and later the system keeps its splash over the app until it
/// is told to take it away, and tells the app what it drew and where first.
/// So the frame under it can be made to match, drawn, and only then can the
/// splash go: it goes from over an identical picture. A splash that showed
/// nothing is reported as bare.
///
/// Everywhere else there is nothing to be told. The launch screen is laid out
/// to match the standard place, and it goes on its own once the first frame
/// is up.
class ArrivalHandoff {
  ArrivalHandoff([this._channel = const MethodChannel(kArrivalChannel)]);

  final MethodChannel _channel;

  /// Called with what the splash showed, before it is taken away. The splash
  /// waits for the future, which should complete once a frame drawn to match
  /// has reached the screen.
  Future<void> Function(SplashReport report)? onReport;

  /// Called once the platform's splash is off the screen.
  VoidCallback? onGone;

  void start() => _channel.setMethodCallHandler(_handle);

  void stop() => _channel.setMethodCallHandler(null);

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'place':
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        final report = SplashReport(
          markInk: _rect(args['mark']),
          nameBox: _rect(args['name']),
          showedMark: args['showedMark'] != false,
          showedName: args['showedName'] != false,
          markPixels: await _image(args['markPixels'], args['markPixelsSize']),
          markPixelsRect: _rect(args['markPixelsRect']),
          namePixels: await _image(args['namePixels'], args['namePixelsSize']),
        );
        final taker = onReport;
        if (taker == null) {
          report.dispose();
        } else {
          await taker(report);
        }
        return null;
      case 'gone':
        onGone?.call();
        return null;
    }
    throw MissingPluginException(call.method);
  }

  /// Premultiplied RGBA of the given size, as Android's bitmaps hold it.
  static Future<ui.Image?> _image(Object? pixels, Object? size) {
    if (pixels is! Uint8List || size is! List || size.length != 2) {
      return Future<ui.Image?>.value();
    }
    final width = (size[0] as num).toInt();
    final height = (size[1] as num).toInt();
    if (width <= 0 || height <= 0 || pixels.length != width * height * 4) {
      return Future<ui.Image?>.value();
    }
    final decoded = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      decoded.complete,
    );
    return decoded.future;
  }

  static Rect? _rect(Object? value) {
    if (value is! List || value.length != 4) return null;
    final sides = [for (final side in value) (side as num).toDouble()];
    return Rect.fromLTRB(sides[0], sides[1], sides[2], sides[3]);
  }
}

/// Completes once a frame scheduled now has been drawn and the one after it
/// has begun, which is as close as Dart can come to knowing the first one is
/// on the glass.
Future<void> framesOnGlass() async {
  final binding = SchedulerBinding.instance;
  binding.scheduleFrame();
  await binding.endOfFrame;
  binding.scheduleFrame();
  await binding.endOfFrame;
}
