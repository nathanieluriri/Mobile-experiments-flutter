import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/arrival/arrival.dart';
import 'package:quire/arrival/arrival_geometry.dart';
import 'package:quire/arrival/arrival_handoff.dart';
import 'package:quire/arrival/arrival_motion.dart';
import 'package:quire/arrival/arrival_painter.dart';
import 'package:quire/arrival/quire_mark.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/widgets/quire_spinner.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';

import 'desk_test.dart' show deskApp;
import 'support/golden.dart';

const _launch = 'ios/Runner/Assets.xcassets';
const _end = 1100.0;

/// Phones the first frame is held to the launch screen on: this app's own,
/// a common Android size, and one whose middle falls between two points.
const _phones = <Size>[Size(402, 874), Size(360, 800), Size(412, 915)];

class _Pixels {
  _Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;

  List<int> at(int x, int y) {
    final i = (y * width + x) * 4;
    return bytes.sublist(i, i + 4);
  }
}

Future<_Pixels> _decode(WidgetTester tester, String path) async {
  return (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return _Pixels(image.width, image.height, data!.buffer.asUint8List());
  }))!;
}

Future<_Pixels> _grab(WidgetTester tester, GlobalKey key, double ratio) async {
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _Pixels(image.width, image.height, data!.buffer.asUint8List());
  }))!;
}

Future<ui.FragmentShader> _shader(WidgetTester tester) async {
  final program = await tester.runAsync(
    () => ui.FragmentProgram.fromAsset(kArrivalShader),
  );
  return program!.fragmentShader();
}

/// Paints [pose] over the whole of a [size] screen at [ratio], and reads it.
Future<_Pixels> _paint(
  WidgetTester tester,
  Size size,
  ArrivalPose pose, {
  ui.FragmentShader? shader,
  ArrivalGeometry? geometry,
  double ratio = 2,
}) async {
  tester.view
    ..devicePixelRatio = ratio
    ..physicalSize = size * ratio;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: CustomPaint(
        size: size,
        painter: ArrivalPainter(
          pose: pose,
          geometry: geometry ?? ArrivalGeometry.standard(size),
          shader: shader,
          pixelRatio: ratio,
        ),
      ),
    ),
  );
  return _grab(tester, key, ratio);
}

/// [over] laid on the ground, as the launch screen shows it.
List<int> _onGround(List<int> over) {
  final a = over[3] / 255;
  int mix(int channel, double ground) =>
      (over[channel] * a + ground * 255 * (1 - a)).round();
  return [
    mix(0, AppColors.ground.r),
    mix(1, AppColors.ground.g),
    mix(2, AppColors.ground.b),
    255,
  ];
}

int _worst(List<int> a, List<int> b) => [
  for (var c = 0; c < 4; c++) (a[c] - b[c]).abs(),
].reduce(math.max);

/// The rect, in logical pixels, covered at least half by the mark's colour.
Rect _inkOf(_Pixels pixels, double ratio) {
  var left = pixels.width, top = pixels.height, right = -1, bottom = -1;
  for (var y = 0; y < pixels.height; y++) {
    for (var x = 0; x < pixels.width; x++) {
      final p = pixels.at(x, y);
      // The mark is the one purple on the screen: half covered, its blue
      // stands well clear of its green, which the name's grey never does.
      if (p[2] - p[1] > 0x21 && p[2] > 0x8A) {
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
  }
  return Rect.fromLTRB(left / ratio, top / ratio, (right + 1) / ratio, (bottom + 1) / ratio);
}

/// The app's own phone, at its own pixel ratio, and the neighbourhood of the
/// mark on it, which is where everything the goo does happens until it
/// swells.
const _screen = Size(402, 874);
const _around = Rect.fromLTWH(125, 350, 152, 175);
const _screenRatio = 3.0;

/// The overlay around the mark on the app's own phone: the mark is moved
/// into a small canvas rather than the whole screen painted.
Future<_Pixels> _paintAround(
  WidgetTester tester,
  ArrivalPose pose,
  ui.FragmentShader shader,
) {
  final full = ArrivalGeometry.standard(_screen);
  return _paint(
    tester,
    _around.size,
    pose,
    shader: shader,
    geometry: ArrivalGeometry(
      markBox: full.markBox.shift(-_around.topLeft),
      nameBox: full.nameBox.shift(-_around.topLeft),
    ),
    ratio: _screenRatio,
  );
}

/// [pose] as the goo alone draws it, with nothing laid over it and its holes
/// still the ground's colour, so two of them can be held to each other.
ArrivalPose _gooOf(ArrivalPose pose) => ArrivalPose(
  nameOpacity: 0,
  nameDrop: 0,
  exactMark: 0,
  window: 0,
  swell: pose.swell,
  gooOutline: pose.gooOutline,
  gooHole: pose.gooHole,
  rim: pose.rim,
  morph: pose.morph,
  panes: pose.panes,
  blob: pose.blob,
  blobCorner: pose.blobCorner,
  settle: pose.settle,
  join: pose.join,
  reach: pose.reach,
  opening: pose.opening,
  stubRound: pose.stubRound,
  zip: pose.zip,
  flapMelt: pose.flapMelt,
  deskScale: pose.deskScale,
);

/// How much of each pixel is the mark's colour and how much of it is open
/// onto what lies under the arrival, from a frame of the overlay alone.
class _Cover {
  _Cover(_Pixels pixels, double window)
    : width = pixels.width,
      height = pixels.height,
      ink = Float64List(pixels.width * pixels.height),
      open = Float64List(pixels.width * pixels.height) {
    final ground = AppColors.ground.b;
    final mark = AppColors.accentBright.b;
    for (var i = 0; i < ink.length; i++) {
      final alpha = pixels.bytes[i * 4 + 3] / 255;
      open[i] = window > 0.02 ? ((1 - alpha) / window).clamp(0.0, 1.0) : 0;
      final blue = alpha > 0 ? pixels.bytes[i * 4 + 2] / 255 / alpha : ground;
      ink[i] = ((blue - ground) / (mark - ground)).clamp(0.0, 1.0);
    }
  }

  final int width;
  final int height;
  final Float64List ink;
  final Float64List open;

  List<bool> get holes => [for (final o in open) o > 0.5];

  List<bool> get inked => [
    for (var i = 0; i < ink.length; i++) open[i] <= 0.5 && ink[i] > 0.5,
  ];

  List<bool> get bare => [
    for (var i = 0; i < ink.length; i++) open[i] <= 0.5 && ink[i] <= 0.5,
  ];

  /// The connected regions of [mask], each as its pixels' indices.
  List<List<int>> regions(List<bool> mask) {
    final seen = List<bool>.filled(mask.length, false);
    final found = <List<int>>[];
    for (var start = 0; start < mask.length; start++) {
      if (!mask[start] || seen[start]) continue;
      final region = <int>[];
      final stack = [start];
      seen[start] = true;
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        region.add(i);
        final x = i % width;
        final y = i ~/ width;
        for (final (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]) {
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          final j = ny * width + nx;
          if (mask[j] && !seen[j]) {
            seen[j] = true;
            stack.add(j);
          }
        }
      }
      found.add(region);
    }
    return found;
  }

  bool touchesEdge(List<int> region) => region.any((i) {
    final x = i % width;
    final y = i ~/ width;
    return x == 0 || y == 0 || x == width - 1 || y == height - 1;
  });

  /// [mask] grown by [by] pixels in every direction, square.
  List<bool> grown(List<bool> mask, int by) {
    var grown = List<bool>.of(mask);
    for (var step = 0; step < by; step++) {
      final next = List<bool>.of(grown);
      for (var i = 0; i < grown.length; i++) {
        if (grown[i]) continue;
        final x = i % width;
        final y = i ~/ width;
        for (var dy = -1; dy <= 1 && !next[i]; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
            if (grown[ny * width + nx]) {
              next[i] = true;
              break;
            }
          }
        }
      }
      grown = next;
    }
    return grown;
  }

  /// Where the outer edge of the mark's left side crosses each row, to a
  /// fraction of a pixel.
  double leftEdge(int row) {
    for (var x = 1; x < width; x++) {
      final here = ink[row * width + x] * (1 - open[row * width + x]);
      if (here >= 0.5) {
        final before = ink[row * width + x - 1] * (1 - open[row * width + x - 1]);
        return x - (here - 0.5) / math.max(here - before, 1e-6);
      }
    }
    return double.nan;
  }
}

/// A child whose state the arrival must never throw away.
class _Counter extends StatefulWidget {
  const _Counter({this.onTap});

  final VoidCallback? onTap;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {
      setState(() => taps++);
      widget.onTap?.call();
    },
    child: const ColoredBox(color: Color(0xFF203040), child: SizedBox.expand()),
  );
}

ArrivalPainter? _painter(WidgetTester tester) {
  final found = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is ArrivalPainter,
  );
  if (found.evaluate().isEmpty) return null;
  return tester.widget<CustomPaint>(found).painter! as ArrivalPainter;
}

Future<void> _pumpArrival(
  WidgetTester tester,
  ValueNotifier<bool> ready, {
  Widget child = const _Counter(),
  bool stillness = false,
  bool handsOver = false,
}) async {
  tester.view
    ..devicePixelRatio = kDpr
    ..physicalSize = kPhone.logical * kDpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: kPhone.logical,
        devicePixelRatio: kDpr,
        disableAnimations: stillness,
      ),
      child: Arrival(ready: ready, handsOver: handsOver, child: child),
    ),
  );
}

Future<void> _platformSays(
  WidgetTester tester,
  String method, [
  Object? arguments,
]) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
  kArrivalChannel,
  const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
  (_) {},
);

/// Advances until the reveal has left the resting pose, and says how long
/// that took.
Future<int> _untilMoving(WidgetTester tester) async {
  for (var ms = 0; ms < 5000; ms += 16) {
    final painter = _painter(tester);
    if (painter != null && !identical(painter.pose, ArrivalPose.rest)) {
      return ms;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('The arrival never moved');
}

/// The opacity the arrival is lifting off at, or null when it is not.
double? _liftingOff(WidgetTester tester) {
  final fading = find.descendant(
    of: find.byType(Arrival),
    matching: find.byType(Opacity),
  );
  if (fading.evaluate().isEmpty) return null;
  return tester.widget<Opacity>(fading).opacity;
}

/// Advances until the arrival has begun to leave, through the goo or by
/// lifting off, and says how long that took.
Future<int> _untilLeaving(WidgetTester tester) async {
  for (var ms = 0; ms < 5000; ms += 16) {
    final painter = _painter(tester);
    if (painter == null || !identical(painter.pose, ArrivalPose.rest)) {
      return ms;
    }
    if ((_liftingOff(tester) ?? 1) < 1) return ms;
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('The arrival never left');
}

void main() {
  group('the first frame is the launch screen', () {
    for (final size in _phones) {
      testWidgets('pixel for pixel on a ${size.width.toInt()} by '
          '${size.height.toInt()} screen', (tester) async {
        const ratio = 2.0;
        final frame = await _paint(tester, size, ArrivalPose.rest);
        final mark = await _decode(tester, '$_launch/LaunchMark.imageset/LaunchMark@2x.png');
        final name = await _decode(tester, '$_launch/LaunchName.imageset/LaunchName@2x.png');
        final geometry = ArrivalGeometry.standard(size);
        var worst = 0;
        for (var y = 0; y < frame.height; y++) {
          for (var x = 0; x < frame.width; x++) {
            final lx = x / ratio;
            final ly = y / ratio;
            List<int> expected;
            final inMark = geometry.markBox.contains(Offset(lx, ly));
            final inName = geometry.nameBox.contains(Offset(lx, ly));
            if (inMark) {
              expected = _onGround(mark.at(
                (x - geometry.markBox.left * ratio).round(),
                (y - geometry.markBox.top * ratio).round(),
              ));
            } else if (inName) {
              expected = _onGround(name.at(
                (x - geometry.nameBox.left * ratio).round(),
                (y - geometry.nameBox.top * ratio).round(),
              ));
            } else {
              expected = _onGround(const [0, 0, 0, 0]);
            }
            worst = math.max(worst, _worst(frame.at(x, y), expected));
          }
        }
        // The launch images are stored unpremultiplied in eight bits, so an
        // edge pixel can come back a few levels off. Nothing else may differ.
        expect(worst, lessThanOrEqualTo(6));
      });
    }

    testWidgets('and lands where Android measured its own splash', (
      tester,
    ) async {
      const size = Size(412, 915);
      final measured = const Rect.fromLTWH(143.2, 371.9, 127.1, 142.8);
      final geometry = ArrivalGeometry.measured(size, markInk: measured);
      final frame = await _paint(
        tester,
        size,
        ArrivalPose.rest,
        geometry: geometry,
        ratio: 3,
      );
      final ink = _inkOf(frame, 3);
      expect(ink.left, closeTo(measured.left, 0.5));
      expect(ink.top, closeTo(measured.top, 0.5));
      expect(ink.right, closeTo(measured.right, 0.5));
      expect(ink.bottom, closeTo(measured.bottom, 0.5));
    });
  });

  group('the goo', () {
    testWidgets('loads, rather than leaving the arrival to fade instead', (
      tester,
    ) async {
      expect(await _shader(tester), isNotNull);
    });

    testWidgets('draws the resting mark as the vector does', (tester) async {
      final shader = await _shader(tester);
      const size = Size(402, 874);
      final vector = await _paint(tester, size, ArrivalPose.rest);
      const withoutVector = ArrivalPose(
        nameOpacity: 1,
        nameDrop: 0,
        exactMark: 0,
        window: 0,
        swell: 1,
        gooOutline: 0,
        gooHole: 0,
        rim: 0,
        morph: 0,
        panes: [PanePose.rest, PanePose.rest, PanePose.rest, PanePose.rest],
        blob: Rect.zero,
        blobCorner: 0,
        settle: 0,
        join: 0,
        reach: 0,
        opening: 0,
        stubRound: 0,
        zip: 0,
        flapMelt: 0,
        deskScale: kArrivalDeskScale,
      );
      final goo = await _paint(tester, size, withoutVector, shader: shader);
      var edges = 0;
      var worst = 0;
      for (var y = 0; y < vector.height; y++) {
        for (var x = 0; x < vector.width; x++) {
          final d = _worst(vector.at(x, y), goo.at(x, y));
          worst = math.max(worst, d);
          if (d > 48) edges++;
        }
      }
      // The dog eared pane's two short bevels are drawn as chords within a
      // thirtieth of a unit of the curve. Nothing differs by more than
      // antialiasing.
      expect(edges, lessThan(40), reason: 'worst $worst');
    });

    testWidgets('starts from the resting mark without a jump', (tester) async {
      final shader = await _shader(tester);
      const size = Size(402, 874);
      final geometry = ArrivalGeometry.standard(size);
      final rest = await _paint(tester, size, ArrivalPose.rest);
      final first = await _paint(
        tester,
        size,
        arrivalPoseAt(1000 / 60, geometry, size),
        shader: shader,
      );
      final mark = geometry.markBox;
      final name = geometry.nameBox;
      var markWorst = 0;
      var nameWorst = 0;
      for (var y = 0; y < rest.height; y++) {
        for (var x = 0; x < rest.width; x++) {
          final at = Offset(x / 2, y / 2);
          final d = _worst(rest.at(x, y), first.at(x, y));
          if (name.contains(at)) {
            nameWorst = math.max(nameWorst, d);
          } else {
            expect(mark.contains(at) || d == 0, isTrue, reason: 'moved at $at');
            markWorst = math.max(markWorst, d);
          }
        }
      }
      // A sixtieth of a second in, the mark has barely begun to soften and
      // the goo is showing through the vector by less than a fifth.
      expect(markWorst, lessThanOrEqualTo(16));
      // The name has sunk a tenth of a point, which moves a horizontal edge
      // a quarter of a pixel and no more.
      expect(nameWorst, lessThanOrEqualTo(64));
    });

    testWidgets('has passed every corner of the screen before it goes', (
      tester,
    ) async {
      final shader = await _shader(tester);
      for (final size in _phones) {
        final geometry = ArrivalGeometry.standard(size);
        final covered =
            kArrivalSwellFrom + kArrivalCovered * (_end - kArrivalSwellFrom);
        for (final ms in [covered, _end - 1]) {
          final frame = await _paint(
            tester,
            size,
            arrivalPoseAt(ms, geometry, size),
            shader: shader,
          );
          var showing = 0;
          for (var i = 3; i < frame.bytes.length; i += 4) {
            if (frame.bytes[i] != 0) showing++;
          }
          expect(showing, 0, reason: '$size at $ms ms');
        }
      }
    });

    testWidgets("holds the mark's shape until the exact mark has gone", (
      tester,
    ) async {
      final shader = await _shader(tester);
      final full = ArrivalGeometry.standard(_screen);
      final rest = _Cover(
        await _paintAround(tester, _gooOf(arrivalPoseAt(0.001, full, _screen)), shader),
        0,
      );
      for (var ms = 1000 / 60; ; ms += 1000 / 60) {
        final pose = arrivalPoseAt(ms, full, _screen);
        if (pose.exactMark == 0) break;
        final goo = _Cover(await _paintAround(tester, _gooOf(pose), shader), 0);
        var worst = 0.0;
        for (var i = 0; i < goo.ink.length; i++) {
          worst = math.max(worst, (goo.ink[i] - rest.ink[i]).abs());
        }
        // Under half a pixel of movement anywhere, so the two layers of the
        // hand over are the same shape and no edge shows twice.
        expect(worst, lessThanOrEqualTo(0.5), reason: 'at $ms ms');
      }
    });

    testWidgets('opens only out of holes already there, and never faster '
        'than an edge can be followed', (tester) async {
      final shader = await _shader(tester);
      final full = ArrivalGeometry.standard(_screen);
      _Cover? last;
      for (var ms = 100.0; ms <= 480; ms += 1000 / 120) {
        final pose = arrivalPoseAt(ms, full, _screen);
        final cover = _Cover(await _paintAround(tester, pose, shader), pose.window);
        final holes = cover.holes;
        if (last != null) {
          final before = last.holes;
          for (final region in cover.regions(holes)) {
            expect(
              region.any((i) => before[i]),
              isTrue,
              reason: 'a hole opened inside the ink at $ms ms',
            );
          }
          // Three points a frame at 120 frames a second.
          final reach = last.grown(before, (3 * _screenRatio).round());
          var outrun = 0;
          for (var i = 0; i < holes.length; i++) {
            if (holes[i] && !reach[i]) outrun++;
          }
          expect(outrun, 0, reason: 'an edge outran the eye at $ms ms');
        }
        if (ms >= 200) {
          final shut = cover.regions(cover.bare).where((r) => !cover.touchesEdge(r));
          expect(shut, isEmpty, reason: 'ground shut inside the goo at $ms ms');
        }
        // The panes are one body once their inner corners have met.
        if (ms >= 180) {
          expect(
            cover.regions(cover.inked).length,
            1,
            reason: 'the goo is in more than one piece at $ms ms',
          );
        }
        last = cover;
      }
    });

    testWidgets('softens every edge smoothly, without stair steps', (
      tester,
    ) async {
      final shader = await _shader(tester);
      final full = ArrivalGeometry.standard(_screen);
      // The rows of the dog eared pane's left side, from below its ear to its
      // foot, bevel and all.
      final top = ((full.markBox.top + 82 * full.unit - _around.top) * _screenRatio).round();
      final bottom = ((full.markBox.top + 124 * full.unit - _around.top) * _screenRatio).round();
      for (var ms = 0.0; ms <= 520; ms += 1000 / 60) {
        final pose = arrivalPoseAt(ms, full, _screen);
        final cover = _Cover(await _paintAround(tester, pose, shader), pose.window);
        final edge = [for (var y = top; y <= bottom; y++) cover.leftEdge(y)];
        for (var i = 1; i < edge.length - 1; i++) {
          final bend = edge[i + 1] - 2 * edge[i] + edge[i - 1];
          expect(
            bend.abs(),
            lessThan(1.2),
            reason: 'a step in the left edge at row ${top + i}, $ms ms',
          );
        }
      }
    });

    test('is one motion, with nothing jumping between frames', () {
      const size = Size(402, 874);
      final geometry = ArrivalGeometry.standard(size);
      ArrivalPose? last;
      for (var ms = 0.0; ms < _end; ms += 1000 / 60) {
        final pose = arrivalPoseAt(ms, geometry, size);
        if (last != null) {
          expect(pose.swell, greaterThanOrEqualTo(last.swell));
          expect((pose.window - last.window).abs(), lessThan(0.2));
          expect((pose.settle - last.settle).abs(), lessThan(0.2));
          expect((pose.reach - last.reach).abs(), lessThan(0.2));
          expect((pose.opening - last.opening).abs(), lessThan(4));
          expect((pose.morph - last.morph).abs(), lessThan(0.2));
          expect((pose.nameOpacity - last.nameOpacity).abs(), lessThan(0.2));
          // Two pictures of the same shape, so a quicker blend is no jump.
          expect((pose.exactMark - last.exactMark).abs(), lessThan(0.35));
          expect((pose.deskScale - last.deskScale).abs(), lessThan(0.01));
          for (var i = 0; i < 4; i++) {
            expect(
              (pose.panes[i].holeScale - last.panes[i].holeScale).abs(),
              lessThan(0.05),
            );
          }
        }
        last = pose;
      }
      // The desk is back where it stays some frames before the end, so
      // nothing under the arrival moves as it is taken away.
      for (var ms = 1000.0; ms <= _end; ms += 1000 / 60) {
        expect(arrivalPoseAt(ms, geometry, size).deskScale, 1);
      }
    });
  });

  group('the arrival', () {
    testWidgets('holds the mark until the screen under it is ready', (
      tester,
    ) async {
      final ready = ValueNotifier<bool>(false);
      await _pumpArrival(tester, ready);
      await tester.pump(const Duration(seconds: 3));
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));

      final state = tester.state<_CounterState>(find.byType(_Counter));
      ready.value = true;
      await _untilMoving(tester);
      await tester.pump(kArrivalReveal);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painter(tester), isNull);
      // The app under it was never rebuilt from scratch.
      expect(tester.state<_CounterState>(find.byType(_Counter)), same(state));
    });

    testWidgets('waits for Android to take its splash away', (tester) async {
      final ready = ValueNotifier<bool>(true);
      await _pumpArrival(tester, ready, handsOver: true);
      // Until the splash has said what it showed, the frame under it shows
      // nothing, since the splash may have had no mark to match.
      expect(_painter(tester)!.showMark, 0);
      expect(_painter(tester)!.showName, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));

      // Android reports where it really drew the mark, a little off the
      // standard place, and waits for the frame drawn to match.
      final standard = ArrivalGeometry.standard(kPhone.logical);
      final ink = Rect.fromLTRB(
        standard.place(QuireMark.ink.topLeft).dx + 1.5,
        standard.place(QuireMark.ink.topLeft).dy - 2,
        standard.place(QuireMark.ink.bottomRight).dx + 1.5,
        standard.place(QuireMark.ink.bottomRight).dy - 2,
      );
      var answered = false;
      unawaited(
        tester.binding.defaultBinaryMessenger
            .handlePlatformMessage(
              kArrivalChannel,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('place', <String, Object?>{
                  'mark': [ink.left, ink.top, ink.right, ink.bottom],
                  'showedMark': true,
                  'showedName': true,
                }),
              ),
              (_) => answered = true,
            ),
      );
      await tester.pump();
      expect(answered, isFalse);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(answered, isTrue);
      expect(_painter(tester)!.showMark, 1);
      expect(_painter(tester)!.showName, 1);
      final placed = _painter(tester)!.geometry;
      expect(placed.place(QuireMark.ink.topLeft).dx, closeTo(ink.left, 1e-6));
      expect(placed.place(QuireMark.ink.topLeft).dy, closeTo(ink.top, 1e-6));

      // However long Android takes to lift its splash, nothing moves under
      // it: a reveal started there would be half over when the splash went.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));
      expect(_liftingOff(tester), isNull);

      await _platformSays(tester, 'gone');
      expect(await _untilMoving(tester), lessThan(50));
    });

    testWidgets("shows Android's own splash pixels until it moves", (
      tester,
    ) async {
      Future<(Uint8List, int, int)> premultiplied(String path) async {
        return (await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(
            File(path).readAsBytesSync(),
          );
          final image = (await codec.getNextFrame()).image;
          final data = await image.toByteData();
          return (data!.buffer.asUint8List(), image.width, image.height);
        }))!;
      }

      final key = GlobalKey();
      tester.view
        ..devicePixelRatio = kDpr
        ..physicalSize = kPhone.logical * kDpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: MediaQueryData(size: kPhone.logical, devicePixelRatio: kDpr),
            child: Arrival(
              ready: ValueNotifier<bool>(true),
              handsOver: true,
              child: const _Counter(),
            ),
          ),
        ),
      );
      // Stand-ins for what the system drew: the launch images, which a test
      // can check pixel for pixel. Read once a frame is up, which the test
      // engine needs before it will hand pixels back.
      final (mark, markWidth, markHeight) = await premultiplied(
        '$_launch/LaunchMark.imageset/LaunchMark@2x.png',
      );
      final (name, nameWidth, nameHeight) = await premultiplied(
        '$_launch/LaunchName.imageset/LaunchName@2x.png',
      );
      final standard = ArrivalGeometry.standard(kPhone.logical);
      final box = standard.markBox;
      var answered = false;
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          kArrivalChannel,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('place', <String, Object?>{
              'showedMark': true,
              'showedName': true,
              'markPixels': mark,
              'markPixelsSize': [markWidth, markHeight],
              'markPixelsRect': [box.left, box.top, box.right, box.bottom],
              'name': [
                standard.nameBox.left,
                standard.nameBox.top,
                standard.nameBox.right,
                standard.nameBox.bottom,
              ],
              'namePixels': name,
              'namePixelsSize': [nameWidth, nameHeight],
            }),
          ),
          (_) => answered = true,
        ),
      );
      // Decoding the pixels takes real time; the frames after it take pumps.
      for (var i = 0; i < 40 && !answered; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(answered, isTrue);
      final painter = _painter(tester)!;
      expect(painter.markPixels, isNotNull);
      expect(painter.namePixels, isNotNull);
      expect(painter.pose, same(ArrivalPose.rest));

      final frame = await _grab(tester, key, kDpr);
      final expectedMark = await _decode(
        tester,
        '$_launch/LaunchMark.imageset/LaunchMark@2x.png',
      );
      var worst = 0;
      for (var y = 0; y < markHeight; y++) {
        for (var x = 0; x < markWidth; x++) {
          worst = math.max(
            worst,
            _worst(
              frame.at((box.left * kDpr).round() + x, (box.top * kDpr).round() + y),
              _onGround(expectedMark.at(x, y)),
            ),
          );
        }
      }
      expect(worst, lessThanOrEqualTo(2));
    });

    testWidgets('leaves on its own a little after a launch screen that does', (
      tester,
    ) async {
      await _pumpArrival(tester, ValueNotifier<bool>(true));
      expect(_painter(tester)!.showMark, 1);
      final waited = await _untilMoving(tester);
      expect(waited, greaterThanOrEqualTo(kArrivalSplashFade.inMilliseconds));
      expect(waited, lessThan(kArrivalSplashFade.inMilliseconds + 100));
    });

    testWidgets('never shows a mark Android did not, however long it is silent', (
      tester,
    ) async {
      // Android said it owned a splash and then never spoke of it again, as
      // a relaunch that skips the splash would.
      await _pumpArrival(tester, ValueNotifier<bool>(true), handsOver: true);
      final shown = <double>{};
      var waited = 0;
      while (_painter(tester) != null && waited < 5000) {
        shown
          ..add(_painter(tester)!.showMark)
          ..add(_painter(tester)!.showName);
        if (!identical(_painter(tester)!.pose, ArrivalPose.rest)) {
          fail('the goo played over a mark that was never on the screen');
        }
        await tester.pump(const Duration(milliseconds: 16));
        waited += 16;
      }
      expect(shown, {0});
      expect(
        waited,
        greaterThanOrEqualTo(kArrivalHandoffBackstop.inMilliseconds),
      );
      expect(
        waited,
        lessThan(
          kArrivalHandoffBackstop.inMilliseconds +
              kArrivalQuietReveal.inMilliseconds +
              100,
        ),
      );
    });

    testWidgets('lifts off without the goo for anyone who asked for stillness', (
      tester,
    ) async {
      await _pumpArrival(tester, ValueNotifier<bool>(true), stillness: true);
      final poses = <ArrivalPose>{};
      final scales = <double>{};
      for (var ms = 0; ms < 1000; ms += 16) {
        final painter = _painter(tester);
        if (painter != null) poses.add(painter.pose);
        final opacity = find.descendant(
          of: find.byType(Arrival),
          matching: find.byType(Opacity),
        );
        if (opacity.evaluate().isNotEmpty) {
          // Lifting off: the desk showing through is where it will stay.
          final transform = tester.widget<Transform>(
            find.descendant(
              of: find.byType(Arrival),
              matching: find.byType(Transform),
            ).first,
          );
          scales.add(transform.transform.getMaxScaleOnAxis());
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(poses, {ArrivalPose.rest});
      expect(scales, {1.0});
      expect(_painter(tester), isNull);
    });

    testWidgets('a splash that came up bare is followed by a bare frame', (
      tester,
    ) async {
      await _pumpArrival(tester, ValueNotifier<bool>(true), handsOver: true);
      expect(_painter(tester)!.showMark, 0);
      await tester.pump(const Duration(milliseconds: 300));
      // What Android sends when its splash had no mark to hand over.
      unawaited(
        _platformSays(tester, 'place', <String, Object?>{
          'showedMark': false,
          'showedName': false,
        }),
      );
      await tester.pump();
      expect(_painter(tester)!.showMark, 0);
      expect(_painter(tester)!.showName, 0);
      await _platformSays(tester, 'gone');
      expect(await _untilLeaving(tester), lessThan(50));
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));
      for (var ms = 0; ms < kArrivalQuietReveal.inMilliseconds + 100; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_painter(tester), isNull);
    });

    testWidgets('lets a finger through once the window is swelling past it', (
      tester,
    ) async {
      var taps = 0;
      await _pumpArrival(
        tester,
        ValueNotifier<bool>(true),
        child: _Counter(onTap: () => taps++),
      );
      await _untilMoving(tester);
      await tester.tapAt(kPhone.logical.center(Offset.zero));
      expect(taps, 0);
      await tester.pump(
        Duration(milliseconds: kArrivalSwellFrom.toInt() + 16),
      );
      await tester.tapAt(kPhone.logical.center(Offset.zero));
      expect(taps, 1);
    });
  });

  group('in the app', () {
    late Directory home;

    setUp(() => home = Directory.systemTemp.createTempSync('quire_arrival'));
    tearDown(() {
      if (home.existsSync()) home.deleteSync(recursive: true);
    });

    void storesIn(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => home.path,
      );
    }

    /// A frame of the test clock with a little real time beside it, for the
    /// reads the desk makes off the disk.
    Future<void> frame(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 4)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('opens onto the desk awake, however slow its first document', (
      tester,
    ) async {
      storesIn(tester);
      // Every shipped document is slow to arrive, the way a large import at
      // the front of the desk is.
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (message) async {
          final key = Uri.decodeFull(
            utf8.decode(
              message!.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            ),
          );
          if (key.startsWith('assets/documents/')) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
          }
          final file = File(key);
          if (!file.existsSync()) return null;
          return ByteData.sublistView(file.readAsBytesSync());
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        ),
      );
      await pumpScreen(tester, const App(splashHandedOver: true));
      // Android hands over before the saved desk has been read.
      unawaited(_platformSays(tester, 'place', <String, Object?>{}));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await _platformSays(tester, 'gone');

      var moving = 0;
      for (var ms = 0; ms < 5000 && _painter(tester) != null; ms += 16) {
        await frame(tester);
        final painter = _painter(tester);
        if (painter == null || identical(painter.pose, ArrivalPose.rest)) {
          continue;
        }
        moving++;
        expect(
          find.descendant(
            of: find.byType(DeskScreen),
            matching: find.byType(QuireSpinner),
          ),
          findsNothing,
          reason: 'the window is open onto a desk still loading',
        );
      }
      expect(moving, greaterThan(30));
      expect(_painter(tester), isNull);
    });

    testWidgets('opens promptly onto a saved desk that cannot be read', (
      tester,
    ) async {
      Directory('${home.path}/imports').createSync(recursive: true);
      File(
        '${home.path}/imports/state.json',
      ).writeAsBytesSync(const [0x7B, 0xFF, 0xFE, 0x7D]);
      storesIn(tester);
      await pumpScreen(tester, const App());
      var ms = 0;
      while (ms < 3000) {
        await frame(tester);
        ms += 16;
        final painter = _painter(tester);
        if (painter == null || !identical(painter.pose, ArrivalPose.rest)) {
          break;
        }
      }
      expect(ms, lessThan(kArrivalSplashFade.inMilliseconds + 200));
      for (var i = 0; i < 100 && _painter(tester) != null; i++) {
        await frame(tester);
      }
      expect(_painter(tester), isNull);
    });
  });

  group('once it has gone', () {
    testWidgets("lets go of the splash's pixels and the goo", (tester) async {
      await _pumpArrival(tester, ValueNotifier<bool>(true), handsOver: true);
      final pixels = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
      var answered = false;
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          kArrivalChannel,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('place', <String, Object?>{
              'markPixels': pixels,
              'markPixelsSize': [4, 4],
              'markPixelsRect': [0.0, 0.0, 2.0, 2.0],
            }),
          ),
          (_) => answered = true,
        ),
      );
      for (var i = 0; i < 40 && !answered; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      final image = _painter(tester)!.markPixels!;
      await _platformSays(tester, 'gone');
      await _untilMoving(tester);
      await tester.pump(kArrivalReveal);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_painter(tester), isNull);
      expect(image.debugDisposed, isTrue);
    });
  });

  group('landing', () {
    testWidgets('is taken away without a pixel changing', (tester) async {
      tester.view
        ..devicePixelRatio = _screenRatio
        ..physicalSize = _screen * _screenRatio;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MediaQuery(
            data: const MediaQueryData(
              size: _screen,
              devicePixelRatio: _screenRatio,
            ),
            child: Arrival(
              ready: ValueNotifier<bool>(true),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: ColoredBox(
                  color: const Color(0xFF203040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 18; i++)
                        Padding(
                          padding: EdgeInsets.fromLTRB(13 + i * 0.37, 7, 0, 0),
                          child: Text('line $i under the window'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _untilMoving(tester);
      await tester.pump(Duration(milliseconds: kArrivalReveal.inMilliseconds - 90));
      _Pixels? before;
      while (_painter(tester) != null) {
        before = await _grab(tester, key, _screenRatio);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final after = await _grab(tester, key, _screenRatio);
      var changed = 0;
      for (var i = 0; i < after.bytes.length; i++) {
        if (after.bytes[i] != before!.bytes[i]) changed++;
      }
      expect(changed, 0);
    });
  });

  group('under the platform asking for less motion', () {
    testWidgets('still lifts off over a quiet moment, not in a cut', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      tester.view
        ..devicePixelRatio = kDpr
        ..physicalSize = kPhone.logical * kDpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Arrival(ready: ValueNotifier<bool>(true), child: const _Counter()),
      );
      var between = 0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final opacity = _liftingOff(tester);
        if (opacity != null && opacity > 0 && opacity < 1) between++;
      }
      expect(between, greaterThanOrEqualTo(10));
      expect(_painter(tester), isNull);
    });
  });

  group('a cold start', () {
    testWidgets('comes through the mark onto the desk', (tester) async {
      final home = Directory.systemTemp.createTempSync('quire_arrival');
      addTearDown(() => home.deleteSync(recursive: true));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => home.path,
      );
      await pumpScreen(tester, const App());
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await settle(tester);
      expect(_painter(tester), isNull);
      expect(find.byType(DeskScreen), findsOneWidget);
    });
  });

  group('keyframes', () {
    testWidgets('arrival', (tester) async {
      final store = LibraryStore();
      await pumpScreen(
        tester,
        Arrival(ready: ValueNotifier<bool>(true), child: deskApp(store)),
      );
      await capture(tester, 'arrival__t0000');
      await _untilMoving(tester);
      var at = 16;
      for (final ms in [250, 300, 317, 333, 450, 650, 900]) {
        await pumpMs(tester, ms - at);
        at = ms;
        await capture(tester, 'arrival__t${ms.toString().padLeft(4, '0')}');
      }
      await settle(tester);
    });
  });
}
