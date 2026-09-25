/// What the screen actually shows at a point, for the tests whose question is
/// whether something can be seen rather than whether it is in the tree.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// One painted frame of the whole screen, held as bytes.
class Screen {
  Screen._(this._rgba, this._width, this._height, this._scale);

  final Uint8List _rgba;
  final int _width;
  final int _height;

  /// Image pixels per logical point.
  final double _scale;

  /// Paints the screen as it stands after the last pump.
  static Future<Screen> of(WidgetTester tester) async {
    RenderObject box = tester.renderObject(find.byType(WidgetsApp).first);
    while (!box.isRepaintBoundary) {
      box = box.parent!;
    }
    final layer = box.debugLayer! as OffsetLayer;
    final bounds = box.paintBounds;
    final logicalWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final captured = await tester.runAsync(() async {
      final image = await layer.toImage(bounds);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final held = (data!.buffer.asUint8List(), image.width, image.height);
      image.dispose();
      return held;
    });
    final (rgba, width, height) = captured!;
    return Screen._(rgba, width, height, width / logicalWidth);
  }

  /// The colour at [point], in logical coordinates.
  Color at(Offset point) {
    final x = (point.dx * _scale).floor().clamp(0, _width - 1);
    final y = (point.dy * _scale).floor().clamp(0, _height - 1);
    final i = (y * _width + x) * 4;
    return Color.fromARGB(_rgba[i + 3], _rgba[i], _rgba[i + 1], _rgba[i + 2]);
  }
}

/// Matches a colour within [tolerance] on every channel, out of 255, so a
/// point is judged by what it shows rather than by rounding in the raster.
Matcher looksLike(Color expected, {int tolerance = 3}) =>
    _LooksLike(expected, tolerance);

class _LooksLike extends Matcher {
  const _LooksLike(this.expected, this.tolerance);

  final Color expected;
  final int tolerance;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! Color) return false;
    final a = item.toARGB32();
    final b = expected.toARGB32();
    for (final shift in const <int>[24, 16, 8, 0]) {
      if ((((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs() > tolerance) {
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
    'a colour within $tolerance of '
    '0x${expected.toARGB32().toRadixString(16).padLeft(8, '0')}',
  );

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! Color) return mismatchDescription.add('is not a colour');
    return mismatchDescription.add(
      'is 0x${item.toARGB32().toRadixString(16).padLeft(8, '0')}',
    );
  }
}
