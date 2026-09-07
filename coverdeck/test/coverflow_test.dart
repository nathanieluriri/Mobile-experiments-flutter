import 'package:coverdeck/app.dart';
import 'package:coverdeck/data/albums.dart';
import 'package:coverdeck/widgets/coverflow/cover_card.dart';
import 'package:coverdeck/widgets/coverflow/coverflow_constants.dart';
import 'package:coverdeck/widgets/coverflow/coverflow_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Deck geometry on the phone the goldens are judged at.
final _size = coverSize(kPhone.logical.width);
final _spacing = _size * 0.36;
final _centerGap = _size * 0.3;

Future<CoverflowController> _pumpDeckAt(WidgetTester tester, double scrollX) async {
  final controller = CoverflowController(vsync: const TestVSync(), count: albums.length);
  addTearDown(controller.dispose);
  controller.dragTo(scrollX);
  await pumpScreen(tester, App(deckController: controller));
  return controller;
}

void main() {
  testWidgets('deck halfway between the first two covers', (tester) async {
    await _pumpDeckAt(tester, 0.49);
    await capture(tester, 'coverflow__drag_half');
  });

  testWidgets('deck halfway into the warm end of the wash', (tester) async {
    await _pumpDeckAt(tester, 2.49);
    await capture(tester, 'coverflow__drag_two_half');
  });

  testWidgets('deck settled on the fourth album', (tester) async {
    await _pumpDeckAt(tester, 3);
    expect(find.text('Violet Hours'), findsOneWidget);
    await capture(tester, 'coverflow__album3');
  });

  group('cover geometry', () {
    CoverCard card(int index, double scrollX) => CoverCard(
          album: albums[index],
          index: index,
          scrollX: scrollX,
          size: _size,
          spacing: _spacing,
          centerGap: _centerGap,
          containerWidth: kPhone.logical.width,
        );

    test('the focused cover is flat, centred and opaque', () {
      final focused = card(0, 0);
      expect(focused.distance, 0);
      expect(focused.travel, 0);
      expect(focused.tiltDegrees, 0);
      expect(focused.scale, 1);
      expect(focused.opacity, 1);
    });

    test('side covers travel further than spacing alone', () {
      // tanh eases the extra centre gap in, so the first neighbour clears the
      // focused cover instead of overlapping it.
      final right = card(1, 0);
      expect(right.travel, greaterThan(_spacing));
      expect(right.travel, closeTo(_spacing + tanh(1.6) * _centerGap, 0.001));
      // The cover on the other side is its mirror image.
      expect(card(0, 1).travel, closeTo(-right.travel, 0.001));
    });

    test('tilt is clamped one cover out', () {
      expect(card(1, 0).tiltDegrees, closeTo(-maxTiltDeg, 0.001));
      expect(card(0, 1).tiltDegrees, closeTo(maxTiltDeg, 0.001));
      expect(card(4, 0).tiltDegrees, closeTo(-maxTiltDeg, 0.001));
      expect(card(0, 0).tiltDegrees, 0);
      expect(card(1, 0.5).tiltDegrees, closeTo(-maxTiltDeg / 2, 0.001));
    });

    test('scale falls to the side scale then eases on', () {
      expect(card(0, 0).scale, 1);
      expect(card(1, 0).scale, closeTo(sideScale, 0.001));
      expect(card(4, 0).scale, closeTo(sideScale * 0.94, 0.001));
      expect(card(9, 0).scale, closeTo(sideScale * 0.94, 0.001));
    });

    test('covers fade out five and a half steps away', () {
      expect(card(0, 0).opacity, 1);
      expect(card(1, 0).opacity, closeTo(0.92, 0.001));
      expect(card(5, 0).opacity, closeTo(0.3, 0.001));
      expect(card(6, 0).opacity, 0);
      expect(card(11, 0).opacity, 0);
    });
  });

  group('deck position', () {
    CoverflowController build() {
      final controller = CoverflowController(vsync: const TestVSync(), count: albums.length);
      addTearDown(controller.dispose);
      return controller;
    }

    test('dragging is clamped just past both ends', () {
      final controller = build();
      controller.dragTo(-4);
      expect(controller.scrollX, controller.minScrollX);
      expect(controller.minScrollX, -0.35);
      controller.dragTo(40);
      expect(controller.scrollX, controller.maxScrollX);
      expect(controller.maxScrollX, albums.length - 0.65);
    });

    test('a release projects the throw forward before rounding', () {
      final controller = build();
      controller.dragTo(1.0);
      // 0.18 seconds of travel at the release speed, then the nearest cover.
      expect(controller.projectedTarget(0), 1, reason: 'no throw, no travel');
      expect(controller.projectedTarget(2.7), 1, reason: '1.0 + 0.486 still rounds down');
      expect(controller.projectedTarget(3), 2, reason: '1.0 + 0.54 tips over');
      expect(controller.projectedTarget(11), 3, reason: '1.0 + 1.98');
      expect(controller.projectedTarget(-11), 0, reason: 'clamped at the first cover');
      expect(controller.projectedTarget(500), albums.length - 1, reason: 'clamped at the last');
    });

    test('the reported index is the nearest cover inside the deck', () {
      final controller = build();
      final seen = <int>[];
      controller.onIndexChanged = seen.add;
      controller.dragTo(0.4);
      expect(controller.index, 0);
      controller.dragTo(0.6);
      expect(controller.index, 1);
      controller.dragTo(controller.minScrollX);
      expect(controller.index, 0, reason: 'the overscroll band still reads as the first cover');
      expect(seen, [1, 0]);
    });

    testWidgets('dragging moves the deck one cover per spacing of travel', (tester) async {
      final controller = await _pumpDeckAt(tester, 0);
      final gesture = await tester.startGesture(const Offset(220, 300));
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(Offset(-_spacing, 0));
      await tester.pump();
      expect(controller.scrollX, closeTo(1, 0.001), reason: 'travel past the slop maps one to one');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('tapping a side cover brings it forward', (tester) async {
      final controller = await _pumpDeckAt(tester, 0);
      // A point on the cover to the right of the focused one.
      await tester.tapAt(Offset(220 + _centerGap + _spacing, 300));
      await tester.pump();
      await pumpMs(tester, 1200);
      expect(controller.index, 1);
      expect(find.text('Crowd Theory'), findsOneWidget);
    });

    testWidgets('tapping the focused cover does nothing', (tester) async {
      final controller = await _pumpDeckAt(tester, 0);
      await tester.tapAt(const Offset(220 + 40, 300));
      await tester.pump();
      await pumpMs(tester, 1200);
      expect(controller.scrollX, 0);
    });
  });
}
