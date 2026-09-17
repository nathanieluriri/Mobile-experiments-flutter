import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/painting/cell_goo_painter.dart';
import 'package:quire/screens/reader/bodies/sheet_choice.dart';

const _frame = 1 / 60;

Rect _cell(int row, int column) =>
    Rect.fromLTWH(column * 118.0, row * 34.0, 118, 34);

/// Every frame of a choice until it rests, with [script] run at the start of
/// each frame, the way the grid's ticker drives it.
List<ChoiceFrame> _play(
  SheetChoice choice,
  void Function(int frame, double now) script, {
  int most = 400,
}) {
  final frames = <ChoiceFrame>[];
  var now = 0.0;
  for (var i = 0; i < most; i++) {
    script(i, now);
    choice.step(now);
    frames.add(choice.frameAt(now));
    if (i > 2 && !choice.moving) break;
    now += _frame;
  }
  return frames;
}

double _centreStep(ChoiceFrame a, ChoiceFrame b) {
  final from = a.goo?.body.center;
  final to = b.goo?.body.center;
  if (from == null || to == null) return 0;
  return (to - from).distance;
}

double _sizeStep(ChoiceFrame a, ChoiceFrame b) {
  final from = a.goo?.body;
  final to = b.goo?.body;
  if (from == null || to == null) return 0;
  return math.max(
    (to.width - from.width).abs(),
    (to.height - from.height).abs(),
  );
}

/// The checks every journey has to pass: nothing moves far in one frame,
/// nothing switches on or off, and the neck never thins past where it would
/// break.
void _flows(List<ChoiceFrame> frames) {
  for (var i = 1; i < frames.length; i++) {
    final a = frames[i - 1];
    final b = frames[i];
    expect(_centreStep(a, b), lessThan(40), reason: 'body jumped at $i');
    expect(_sizeStep(a, b), lessThan(12), reason: 'body popped at $i');
    expect((b.fill - a.fill).abs(), lessThan(0.12), reason: 'goo at $i');
    expect(
      (b.ringStrength - a.ringStrength).abs(),
      lessThan(0.12),
      reason: 'ring at $i',
    );
    // A drop drying up takes its neck in with it; otherwise the neck is
    // never thinner than what holds together.
    final goo = b.goo;
    final whole =
        goo != null &&
        math.max(goo.body.width, goo.body.height) >= kCellGooBodyMax;
    if (goo != null && goo.neck > 0 && whole) {
      expect(goo.neck, greaterThanOrEqualTo(kCellGooNeckMin));
    }
  }
}

void main() {
  group('a choice that moves', () {
    for (final to in <(int, int)>[(2, 0), (4, 2), (10, 1), (20, 2), (1, 6)]) {
      test('to row ${to.$1 + 1}, column ${to.$2 + 1}, flows all the way', () {
        final choice = SheetChoice(_cell(1, 0));
        final target = _cell(to.$1, to.$2);
        final frames = _play(choice, (frame, now) {
          if (frame == 0) choice.choose(target, now);
        });
        _flows(frames);
        expect(choice.moving, isFalse);
        expect(frames.last.ring, target);
        expect(frames.last.lit, target);
        expect(frames.last.goo, isNull);
      });
    }

    test('sets off gently rather than at its top speed', () {
      final choice = SheetChoice(_cell(1, 0));
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(_cell(12, 3), now);
      });
      final first = _centreStep(frames[0], frames[1]);
      final later = _centreStep(frames[3], frames[4]);
      expect(first, lessThan(later));
      expect(frames[1].ringStrength, greaterThan(0.9));
    });

    test('is one body with a neck, never two pieces', () {
      final choice = SheetChoice(_cell(1, 0));
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(_cell(20, 2), now);
      });
      final stretched = frames.where((frame) => (frame.goo?.neck ?? 0) > 0);
      expect(stretched, isNotEmpty);
      for (final frame in stretched) {
        final goo = frame.goo!;
        expect(goo.tailRadius, greaterThan(0));
        expect(goo.neck, greaterThanOrEqualTo(kCellGooNeckMin));
      }
    });

    test('a second choice on the way keeps the speed it has', () {
      final choice = SheetChoice(_cell(1, 0));
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(_cell(8, 2), now);
        if (frame == 12) choice.choose(_cell(3, 5), now);
      });
      _flows(frames);
      final before = _centreStep(frames[11], frames[12]);
      final after = _centreStep(frames[12], frames[13]);
      expect(before, greaterThan(4));
      expect(after, greaterThan(before * 0.5));
      expect(frames.last.ring, _cell(3, 5));
    });

    test('letting go on the way coasts and dries up', () {
      final choice = SheetChoice(_cell(1, 0));
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(_cell(9, 1), now);
        if (frame == 10) choice.choose(null, now);
      });
      _flows(frames);
      expect(frames.last.ring, isNull);
      expect(frames.last.lit, isNull);
      expect(frames.last.goo, isNull);
    });
  });

  group('a first choice', () {
    test('condenses as a drop and spreads without stalling', () {
      final choice = SheetChoice(null);
      final cell = _cell(3, 1);
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(cell, now);
      });
      _flows(frames);
      // Growing all the way from nothing to the width of the cell: once it
      // has begun it never stops to think about it.
      var grown = false;
      for (var i = 1; i < frames.length; i++) {
        final width = frames[i].goo?.body.width ?? cell.width;
        if (width >= (cell.width - 6) * 0.9) break;
        final step = _sizeStep(frames[i - 1], frames[i]);
        if (step > 0.5) grown = true;
        if (grown) expect(step, greaterThan(0.3), reason: 'stalled at $i');
      }
      expect(frames.last.ring, cell);
    });
  });

  group('a choice let go', () {
    test('draws the ring in and dries up where it was', () {
      final choice = SheetChoice(_cell(3, 1));
      final frames = _play(choice, (frame, now) {
        if (frame == 0) choice.choose(null, now);
      });
      _flows(frames);
      expect(frames.last.ring, isNull);
      expect(frames.last.lit, isNull);
    });
  });
}
