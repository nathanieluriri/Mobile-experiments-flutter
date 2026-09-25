import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/colors.dart';

import 'desk_test.dart' show deskApp;
import 'support/golden.dart';

const _launch = 'ios/Runner/Assets.xcassets';
const _channel = MethodChannel(kArrivalChannel);
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
      child: Arrival(ready: ready, child: child),
    ),
  );
}

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
        tension: 0,
        stubRound: 0,
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
      // Two short bevels on the dog eared pane are drawn as straight lines,
      // which puts a handful of their edge pixels a shade off. Nothing else
      // differs by more than antialiasing.
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

    test('is one motion, with nothing jumping between frames', () {
      const size = Size(402, 874);
      final geometry = ArrivalGeometry.standard(size);
      ArrivalPose? last;
      for (var ms = 0.0; ms < _end; ms += 1000 / 60) {
        final pose = arrivalPoseAt(ms, geometry, size);
        if (last != null) {
          expect(pose.swell, greaterThanOrEqualTo(last.swell));
          expect((pose.window - last.window).abs(), lessThan(0.2));
          expect((pose.tension - last.tension).abs(), lessThan(0.2));
          expect((pose.morph - last.morph).abs(), lessThan(0.2));
          expect((pose.nameOpacity - last.nameOpacity).abs(), lessThan(0.2));
          expect((pose.exactMark - last.exactMark).abs(), lessThan(0.2));
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
      // Where it ends is where the desk stays.
      expect(last!.deskScale, closeTo(1, 0.0005));
      expect(arrivalPoseAt(_end, geometry, size).deskScale, 1);
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
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'handsOver' ? true : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      final ready = ValueNotifier<bool>(true);
      await _pumpArrival(tester, ready);
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, ['handsOver']);
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
      final placed = _painter(tester)!.geometry;
      expect(placed.place(QuireMark.ink.topLeft).dx, closeTo(ink.left, 1e-6));
      expect(placed.place(QuireMark.ink.topLeft).dy, closeTo(ink.top, 1e-6));
      expect(_painter(tester)!.pose, same(ArrivalPose.rest));

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kArrivalChannel,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('gone')),
        (_) {},
      );
      expect(await _untilMoving(tester), lessThan(50));
    });

    testWidgets("shows Android's own splash pixels until it moves", (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'handsOver' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
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

    testWidgets('waits no longer than its limit once Android says it will hand over', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'handsOver' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      // Both limits are counted from the first frame, whenever the answer lands.
      final ready = ValueNotifier<bool>(true);
      tester.view
        ..devicePixelRatio = kDpr
        ..physicalSize = kPhone.logical * kDpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: kPhone.logical, devicePixelRatio: kDpr),
          child: Arrival(ready: ready, child: const _Counter()),
        ),
        duration: Duration.zero,
      );
      final waited = await _untilMoving(tester);
      expect(
        waited,
        lessThan(kArrivalHandoffLimit.inMilliseconds + 100),
      );
    });

    testWidgets('does not wait for ever on a splash never handed over', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'handsOver' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      await _pumpArrival(tester, ValueNotifier<bool>(true));
      final waited = await _untilMoving(tester);
      expect(waited, greaterThanOrEqualTo(kArrivalHandoffLimit.inMilliseconds));
      expect(
        waited,
        lessThan(kArrivalHandoffLimit.inMilliseconds + 100),
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
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async => call.method == 'handsOver' ? true : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      await _pumpArrival(tester, ValueNotifier<bool>(true));
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          kArrivalChannel,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('place', <String, Object?>{
              'showedMark': false,
              'showedName': false,
            }),
          ),
          (_) {},
        ),
      );
      await tester.pump();
      expect(_painter(tester)!.showMark, 0);
      expect(_painter(tester)!.showName, 0);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kArrivalChannel,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('gone')),
        (_) {},
      );
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
      for (final ms in [250, 450, 650, 900]) {
        await pumpMs(tester, ms - at);
        at = ms;
        await capture(tester, 'arrival__t${ms.toString().padLeft(4, '0')}');
      }
      await settle(tester);
    });
  });
}
