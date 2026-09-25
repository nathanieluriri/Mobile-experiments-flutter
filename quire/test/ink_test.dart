import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/signature_painter.dart';
import 'package:quire/screens/sign/placement_layer.dart';
import 'package:quire/screens/sign/sign_pad.dart';
import 'package:quire/theme/metrics.dart';

import 'sign_test.dart'
    show
        placementApp,
        pressLeasePage,
        scriptSignature,
        scriptStrokes,
        signApp,
        signOnto;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// A straight run of [steps] samples from [from] to [to], so a test can state
/// a speed in points per second rather than in pixels per frame.
List<Offset> _run(Offset from, Offset to, int steps) => <Offset>[
  for (var i = 0; i <= steps; i++) Offset.lerp(from, to, i / steps)!,
];

List<Duration> _ticks(int count, {int ms = 16}) => <Duration>[
  for (var i = 0; i < count; i++) Duration(milliseconds: i * ms),
];

InkStroke _ink(List<Offset> samples) =>
    InkStroke.fromSamples(samples, _ticks(samples.length));

void main() {
  group('the ribbon', () {
    test('a slow hand draws fat and a fast one draws thin', () {
      // Three points every 16 ms is 187 points per second; forty is 2500.
      final slow = _ink(_run(Offset.zero, const Offset(48, 0), 16));
      final fast = _ink(_run(Offset.zero, const Offset(640, 0), 16));

      expect(slow.halfWidths.last, greaterThan(fast.halfWidths.last));
      expect(slow.halfWidths.last, closeTo(kInkWidthSlow / 2, 0.45));
      expect(fast.halfWidths.last, closeTo(kInkWidthFast / 2, 0.001));
    });

    test('width never leaves the two stated ends of the scale', () {
      for (final stroke in scriptStrokes()) {
        for (final half in stroke.halfWidths) {
          expect(half, inInclusiveRange(kInkWidthFast / 2, kInkWidthSlow / 2));
        }
      }
    });

    test('one signature carries real width variation', () {
      final widths = scriptStrokes().first.halfWidths;
      final widest = widths.reduce((a, b) => a > b ? a : b);
      final thinnest = widths.reduce((a, b) => a < b ? a : b);
      expect(widest - thinnest, greaterThan(0.5));
    });

    test('the centre line is resampled to an even step', () {
      // On a straight run the chord between two points is the arc between
      // them, so the step is exact.
      final straight = _ink(_run(Offset.zero, const Offset(180, 0), 9));
      for (var i = 2; i < straight.centre.length - 1; i++) {
        final gap = (straight.centre[i] - straight.centre[i - 1]).distance;
        expect(gap, closeTo(kResampleStep, 0.01));
      }
      // A signature is resampled along its arc, so a chord across a tight
      // turn is shorter than the step, and nowhere is it longer.
      final raw = scriptSignature().first;
      final ink = _ink(raw);
      expect(ink.centre.length, greaterThan(raw.length));
      for (var i = 1; i < ink.centre.length - 1; i++) {
        final gap = (ink.centre[i] - ink.centre[i - 1]).distance;
        expect(gap, lessThanOrEqualTo(kResampleStep + 0.01));
      }
    });

    test('the outline is a closed ribbon, not a stroked line', () {
      final ink = _ink(_run(const Offset(20, 20), const Offset(200, 20), 12));
      final outline = ink.outline();

      expect(outline.length, greaterThan(ink.centre.length * 2));
      expect((outline.first - outline.last).distance, lessThan(0.001));
      final ys = outline.map((p) => p.dy).toList()..sort();
      expect(ys.last - ys.first, closeTo(ink.halfWidths.first * 2, 0.2));
    });

    test('a single tap is a round dot rather than nothing', () {
      final ink = InkStroke.fromSamples(const <Offset>[
        Offset(10, 10),
      ], const <Duration>[Duration.zero]);
      expect(ink.isEmpty, isFalse);
      expect(ink.bounds.width, closeTo(kInkWidthSlow, 0.001));
      expect(ink.bounds.height, closeTo(kInkWidthSlow, 0.001));
    });

    test('a mark keeps its shape at any size', () {
      final mark = SignatureMark.of(scriptStrokes());
      expect(mark.isEmpty, isFalse);
      expect(mark.outlines.length, 2);
      for (final outline in mark.outlines) {
        for (final point in outline) {
          expect(point.dx, inInclusiveRange(-0.001, 1.001));
          expect(point.dy, inInclusiveRange(-0.001, 1.001));
        }
      }
      final small = mark.pathIn(const Rect.fromLTWH(0, 0, 100, 40));
      final large = mark.pathIn(const Rect.fromLTWH(0, 0, 300, 120));
      expect(
        large.getBounds().width / small.getBounds().width,
        closeTo(3, 0.02),
      );
      expect(mark.aspect, closeTo(mark.bounds.height / mark.bounds.width, 1e-9));
    });
  });

  group('drying', () {
    testWidgets('a stroke ends wet and dries over kInkDry', (tester) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      await pumpScreen(tester, signApp(pad));
      await signOnto(tester, pad);

      expect(pad.strokes.length, 2);
      expect(pad.dry, lessThan(0.01));
      await pumpMs(tester, kInkDry.inMilliseconds ~/ 2);
      expect(pad.dry, greaterThan(0));
      expect(pad.dry, lessThan(1));
      await pumpMs(tester, kInkDry.inMilliseconds);
      expect(pad.dry, 1);
    });

    testWidgets('undo takes the last stroke and clear takes them all', (
      tester,
    ) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      await pumpScreen(tester, signApp(pad));
      await signOnto(tester, pad);

      pad.undo();
      expect(pad.strokes.length, 1);
      pad.clear();
      expect(pad.strokes, isEmpty);
      // Undo past the first stroke is not an error, it is simply nothing.
      pad.undo();
      expect(pad.strokes, isEmpty);
    });
  });

  group('the goldens', () {
    testWidgets('ink__t0000 and ink__t0900', (tester) async {
      final pad = SignPadController();
      addTearDown(pad.dispose);
      await pumpScreen(tester, signApp(pad));
      await signOnto(tester, pad);

      await capture(tester, 'ink__t0000');
      await pumpMs(tester, kInkDry.inMilliseconds);
      await capture(tester, 'ink__t0900');
    });

    testWidgets('absorb__t0450', (tester) async {
      final store = await storeFor(kPressLease);
      store.position = 1;
      final page = await pressLeasePage(1);
      final key = GlobalKey<PlacementLayerState>();
      await pumpScreen(tester, placementApp(store, page, key));
      await settle(tester);

      key.currentState!.commit();
      await tester.pump();
      await pumpMs(tester, kAbsorb.inMilliseconds ~/ 2);
      await capture(tester, 'absorb__t0450');

      await pumpMs(tester, kAbsorb.inMilliseconds);
      await settle(tester);
      expect(store.signatures.length, 1);
    });
  });
}
