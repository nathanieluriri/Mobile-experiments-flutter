import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/spinner_painter.dart';
import 'package:quire/widgets/quire_spinner.dart';

import 'support/golden.dart';

void main() {
  group('the spinner loop', () {
    test('stays inside the box it was given', () {
      const size = Size(kSpinnerSize, kSpinnerSize);
      final centre = size.center(Offset.zero);
      final mean = SpinnerPainter.meanRadius(size);
      for (final turns in <double>[0, 0.25, 0.5, 0.75]) {
        for (var i = 0; i <= kSpinnerSegments; i++) {
          final point = SpinnerPainter.pointAt(
            i / kSpinnerSegments,
            turns,
            centre,
            mean,
          );
          final reach = (point - centre).distance + kSpinnerStroke / 2;
          expect(reach, lessThanOrEqualTo(kSpinnerSize / 2 + 0.001));
        }
      }
    });

    test('waves by the stated amount and no more', () {
      const size = Size(kSpinnerSize, kSpinnerSize);
      final centre = size.center(Offset.zero);
      final mean = SpinnerPainter.meanRadius(size);
      var low = double.infinity;
      var high = 0.0;
      for (var i = 0; i <= kSpinnerSegments; i++) {
        final radius =
            (SpinnerPainter.pointAt(
                      i / kSpinnerSegments,
                      0.37,
                      centre,
                      mean,
                    ) -
                    centre)
                .distance;
        low = math.min(low, radius);
        high = math.max(high, radius);
      }
      expect(high - low, closeTo(2 * kSpinnerWave, 0.05));
    });

    test('meets itself at both tips, so neither end is a step', () {
      const size = Size(kSpinnerSize, kSpinnerSize);
      final centre = size.center(Offset.zero);
      final mean = SpinnerPainter.meanRadius(size);
      for (final turns in <double>[0, 0.13, 0.5, 0.91]) {
        final tail = (SpinnerPainter.pointAt(0, turns, centre, mean) - centre)
            .distance;
        final head = (SpinnerPainter.pointAt(1, turns, centre, mean) - centre)
            .distance;
        expect(head, closeTo(tail, 0.001));
      }
    });

    test('leaves a gap of sixty degrees', () {
      expect(360 - kSpinnerSweep, 60);
    });

    test('the squiggle travels rather than riding the arc', () {
      // The wave's phase is read at the arc's own tail. A wave pinned to the
      // arc would sit at the mean radius there every frame, and the whole
      // squiggle would rotate rigidly like a printed shape being spun.
      const size = Size(kSpinnerSize, kSpinnerSize);
      final centre = size.center(Offset.zero);
      final mean = SpinnerPainter.meanRadius(size);
      double tailRadius(double turns) =>
          (SpinnerPainter.pointAt(0, turns, centre, mean) - centre).distance;
      expect(tailRadius(0), closeTo(mean, 0.0001));
      expect(tailRadius(0.25), closeTo(mean + kSpinnerWave, 0.0001));
      expect(tailRadius(0.75), closeTo(mean - kSpinnerWave, 0.0001));
    });

    test('carries the stated number of crests past a fixed point per turn', () {
      expect(kSpinnerCrestsPerTurn, closeTo(9.8, 0.0001));
    });

    testWidgets('turns once every 1100 ms and never rests', (tester) async {
      await pumpScreen(tester, _spinner());
      final painters = <SpinnerPainter>[_painterOf(tester)];
      for (var i = 0; i < 4; i++) {
        await pumpMs(tester, 275);
        painters.add(_painterOf(tester));
      }
      expect(painters.first.turns, closeTo(0, 0.0001));
      expect(painters[1].turns, closeTo(0.25, 0.0001));
      expect(painters[2].turns, closeTo(0.5, 0.0001));
      expect(painters[3].turns, closeTo(0.75, 0.0001));
      // A repeating controller lands back on nought after a whole turn, which
      // is the loop continuing rather than the loop stopping.
      expect(painters[4].turns, closeTo(0, 0.0001));
    });

    testWidgets('spinner keyframes', (tester) async {
      await pumpScreen(tester, _spinner());
      await capture(tester, 'spinner__t0000');
      await pumpMs(tester, 275);
      await pumpMs(tester, 275);
      await capture(tester, 'spinner__t0550');
    });
  });
}

Widget _spinner() => const MaterialApp(
  debugShowCheckedModeBanner: false,
  home: QuireLoading(),
);

SpinnerPainter _painterOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(QuireSpinner),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as SpinnerPainter;
}
