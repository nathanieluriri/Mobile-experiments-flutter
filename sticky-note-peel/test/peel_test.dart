import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/painting/fold_painter.dart';
import 'package:sticky_note_peel/theme/metrics.dart';
import 'package:sticky_note_peel/widgets/action_dock.dart';
import 'package:sticky_note_peel/widgets/shimmer.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';
import 'support/peel.dart';

/// Where the fold point ends up at the end of the peel, in note coordinates.
const _deepFold = Offset(250, 120);

void main() {
  testWidgets('peel keyframes from the top-right corner', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    await capture(tester, 'peel__t0000');

    final drag = PeelDrag(tester, gesture, _deepFold);
    await drag.advanceTo(250);
    await capture(tester, 'peel__t0250');

    await drag.advanceTo(600);
    await capture(tester, 'peel__t0600');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('peel held over the delete action', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    final drag = PeelDrag(tester, gesture, dockButtonCenter(tester, 0));
    await drag.advanceTo(600);
    await pumpMs(tester, 400);
    await capture(tester, 'peel__hover');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a press shorter than the threshold does not peel',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await tester.startGesture(handleCenter(tester, 0));
    await pumpMs(tester, kPeelLongPress.inMilliseconds - 40);
    expect(find.byType(ActionDock), findsNothing);
    await gesture.moveBy(const Offset(-80, 90));
    await pumpMs(tester, 200);
    expect(
      find.byType(ActionDock),
      findsNothing,
      reason: 'the corner only peels after the long press threshold',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('holding past the threshold lifts the note and dims the rest',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    expect(find.byType(ActionDock), findsOneWidget);
    expect(dimOpacityOf(tester, 1), closeTo(kDimmedNoteOpacity, 0.001));
    expect(dimOpacityOf(tester, 0), 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(ActionDock), findsNothing);
    expect(dimOpacityOf(tester, 1), 1);
  });

  testWidgets('the shimmer sweeps the note after it springs back',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    final drag = PeelDrag(tester, gesture, _deepFold);
    await drag.advanceTo(600);
    await gesture.up();
    // The release animations start their clock on the next frame.
    await tester.pump();

    await pumpMs(tester, 320);
    await capture(tester, 'settle__t0320');
    expect(shimmerBandLeft(tester), greaterThan(0));

    await pumpMs(tester, 320);
    expect(
      shimmerBandLeft(tester),
      greaterThan(kNoteWidth),
      reason: 'the band leaves past the right edge',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('the fold sits on the corner of whatever width the note gets',
      (tester) async {
    const narrow = Phone('narrow', Size(300, 700), top: 24, bottom: 24);
    await pumpScreen(tester, const App(), phone: narrow);
    await tester.pump();
    expect(foldOf(tester, 0).dragX, 260 - kFoldRestInset);

    // A window can report one size on its first frame and another once it has
    // settled, so the rest point has to be read from the note, not remembered.
    tester.view.physicalSize = const Size(360, 800) * kDpr;
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(find.byType(StickyNote).at(0)).width, 320);
    expect(foldOf(tester, 0).dragX, 320 - kFoldRestInset);
    expect(foldOf(tester, 0).dragY, kFoldRestInset);
  });

  testWidgets('a cancelled peel puts the note back', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    final drag = PeelDrag(tester, gesture, _deepFold);
    await drag.advanceTo(300);
    expect(find.byType(ActionDock), findsOneWidget);

    await gesture.cancel();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byType(ActionDock),
      findsNothing,
      reason: 'a cancelled pointer must not leave the note lifted',
    );
    expect(dimOpacityOf(tester, 1), 1);
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length));
    final physics = tester.widget<Scrollable>(find.byType(Scrollable).first).physics;
    expect(physics, isNot(isA<NeverScrollableScrollPhysics>()));
  });

  testWidgets('releasing away from the dock keeps every note', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    final drag = PeelDrag(tester, gesture, _deepFold);
    await drag.advanceTo(600);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(StickyNote), findsNWidgets(kNotes.length));
  });
}

/// The fold the note at [index] is currently painting.
FoldPainter foldOf(WidgetTester tester, int index) {
  return tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(StickyNote).at(index),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((paint) => paint.painter)
      .whereType<FoldPainter>()
      .first;
}

/// How far the shimmer band on the first note has travelled from the left edge.
double shimmerBandLeft(WidgetTester tester) {
  final band = tester.widgetList<Shimmer>(
    find.descendant(
      of: find.byType(StickyNote).at(0),
      matching: find.byType(Shimmer),
    ),
  ).first;
  return -kNoteShimmerBand +
      (band.width + kNoteShimmerBand * 2) * band.progress;
}

/// The opacity the note at [index] is drawn with while another note is lifted.
double dimOpacityOf(WidgetTester tester, int index) {
  final opacities = tester.widgetList<Opacity>(
    find.descendant(
      of: find.byType(StickyNote).at(index),
      matching: find.byType(Opacity),
      matchRoot: true,
    ),
  );
  return opacities.isEmpty ? 1 : opacities.first.opacity;
}
