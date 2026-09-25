import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/arrival/arrival.dart';
import 'package:quire/arrival/arrival_bounds.dart';
import 'package:quire/arrival/arrival_geometry.dart';
import 'package:quire/arrival/arrival_motion.dart';
import 'package:quire/arrival/arrival_painter.dart';

const _screen = Size(402, 874);

Future<ui.FragmentShader> _shader(WidgetTester tester) async {
  final program = await tester.runAsync(
    () => ui.FragmentProgram.fromAsset(kArrivalShader),
  );
  return program!.fragmentShader();
}

/// [pose] over the whole screen at [ratio], as raw RGBA.
Future<Uint8List> _render(
  WidgetTester tester,
  ArrivalPose pose,
  ui.FragmentShader shader, {
  required bool bounded,
  ArrivalGeometry? geometry,
  double ratio = 1,
}) async {
  ArrivalPainter.bounded = bounded;
  addTearDown(() => ArrivalPainter.bounded = true);
  tester.view
    ..devicePixelRatio = ratio
    ..physicalSize = _screen * ratio;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: CustomPaint(
        size: _screen,
        painter: ArrivalPainter(
          pose: pose,
          geometry: geometry ?? ArrivalGeometry.standard(_screen),
          shader: shader,
          pixelRatio: ratio,
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }))!;
}

/// How many bytes differ between [a] and [b].
int _differing(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) n++;
  }
  return n;
}

/// A pose with every parameter the shader reads set somewhere in or past
/// the range the reveal uses, so the bound is tried where the motion never
/// goes as well as where it does.
ArrivalPose _wildPose(math.Random random) {
  double r(double lo, double hi) => lo + random.nextDouble() * (hi - lo);
  return ArrivalPose(
    nameOpacity: 0,
    nameDrop: 0,
    exactMark: 0,
    window: r(0, 1),
    swell: r(0.6, 1.6),
    gooOutline: r(0, 30),
    gooHole: r(0, 30),
    rim: r(0, 12),
    morph: random.nextBool() ? 0 : r(0, 1),
    panes: [
      for (var i = 0; i < 4; i++)
        PanePose(
          shift: Offset(r(-30, 30), r(-30, 30)),
          outlineScale: r(0.3, 1.4),
          holeScale: r(0.2, 1.4),
          outlineRound: r(0, 12),
          holeRound: r(0, 12),
        ),
    ],
    blob: Rect.fromCenter(
      center: Offset(r(100, 140), r(110, 150)),
      width: r(0, 120),
      height: r(0, 120),
    ),
    blobCorner: r(0, 1),
    settle: random.nextBool() ? 0 : r(0, 1),
    join: random.nextBool() ? 0 : r(0, 1),
    reach: random.nextBool() ? 0 : r(0, 1),
    opening: random.nextBool() ? 0 : r(0, 20),
    stubRound: r(0, 8),
    zip: r(0, 2),
    flapMelt: r(0, 1),
    deskScale: 1,
  );
}

void main() {
  testWidgets('every frame of the reveal is the same pixel for pixel', (
    tester,
  ) async {
    final shader = await _shader(tester);
    final geometry = ArrivalGeometry.standard(_screen);
    for (var ms = 5.0; ms < kArrivalReveal.inMilliseconds; ms += 15) {
      final pose = arrivalPoseAt(ms, geometry, _screen);
      final whole = await _render(tester, pose, shader, bounded: false);
      final bound = await _render(tester, pose, shader, bounded: true);
      expect(_differing(whole, bound), 0, reason: 'at ${ms}ms');
    }
  });

  testWidgets('and at the app phone ratio, off centre', (tester) async {
    final shader = await _shader(tester);
    final geometry = ArrivalGeometry(
      markBox: const Rect.fromLTWH(40, 260, 288, 288),
      nameBox: const Rect.fromLTWH(150, 780, 102, 30),
    );
    for (final ms in [160.0, 380.0, 520.0, 700.0]) {
      final pose = arrivalPoseAt(ms, geometry, _screen);
      final whole = await _render(tester, pose, shader,
          bounded: false, geometry: geometry, ratio: 3);
      final bound = await _render(tester, pose, shader,
          bounded: true, geometry: geometry, ratio: 3);
      expect(_differing(whole, bound), 0, reason: 'at ${ms}ms');
    }
  });

  testWidgets('poses the reveal never takes are held by the bound too', (
    tester,
  ) async {
    final shader = await _shader(tester);
    final random = math.Random(42);
    for (var i = 0; i < 40; i++) {
      final pose = _wildPose(random);
      final whole = await _render(tester, pose, shader, bounded: false);
      final bound = await _render(tester, pose, shader, bounded: true);
      expect(_differing(whole, bound), 0, reason: 'pose $i');
    }
  });

  test('early frames shade a small part of the screen', () {
    final geometry = ArrivalGeometry.standard(_screen);
    final full = Offset.zero & _screen;
    double share(double ms) {
      final bounds = arrivalBounds(arrivalPoseAt(ms, geometry, _screen),
          geometry, 3)!;
      final shaded = bounds.intersect(full);
      return shaded.isEmpty
          ? 0
          : shaded.width * shaded.height / (full.width * full.height);
    }

    expect(share(100), lessThan(0.3));
    expect(share(300), lessThan(0.4));
  });
}
