import 'package:coverdeck/app.dart';
import 'package:coverdeck/data/albums.dart';
import 'package:coverdeck/widgets/coverflow/coverflow_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

/// Release speed the keyframes below are captured at, in covers per second.
const _releaseVelocity = 6.0;

void main() {
  group('the deck settles onto a cover', () {
    late CoverflowController controller;

    Future<void> release(WidgetTester tester) async {
      controller = CoverflowController(
        vsync: const TestVSync(),
        count: albums.length,
      );
      addTearDown(controller.dispose);
      controller.dragTo(0.6);
      await pumpScreen(tester, App(deckController: controller));
      controller.fling(_releaseVelocity);
      // The frame at the moment of release, which every keyframe counts from.
      await tester.pump();
    }

    for (final ms in const [0, 100, 250, 500]) {
      testWidgets('$ms ms after the release', (tester) async {
        await release(tester);
        if (ms > 0) {
          await pumpMs(tester, ms);
        }
        await capture(tester, 'snap__t${ms.toString().padLeft(4, '0')}');
        await settle(tester);
      });
    }

    testWidgets('overshoots then comes back to rest', (tester) async {
      await release(tester);
      final positions = <double>[];
      for (var i = 0; i < 24; i++) {
        await pumpMs(tester, 50);
        positions.add(controller.scrollX);
      }
      expect(
        positions.any((value) => value > 2),
        isTrue,
        reason: 'a spring with this damping overshoots its target',
      );
      expect(positions.last, closeTo(2, 0.01), reason: 'and settles on it');
      expect(controller.index, 2);
      await settle(tester);
    });

    testWidgets('a slow release stays on the cover it started from', (
      tester,
    ) async {
      await release(tester);
      controller.dragTo(0.6);
      controller.fling(0);
      await tester.pump();
      await pumpMs(tester, 1200);
      expect(controller.scrollX, closeTo(1, 0.01));
      await settle(tester);
    });
  });
}
