import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/theme/metrics.dart';
import 'package:sticky_note_peel/widgets/action_dock.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';
import 'support/peel.dart';

/// Peels the first note and lets go of it over the delete button.
Future<void> _dropOnDelete(WidgetTester tester) async {
  final gesture = await liftNote(tester, 0);
  final drag = PeelDrag(tester, gesture, dockButtonCenter(tester, 0));
  await drag.advanceTo(600);
  await pumpMs(tester, 400);
  await gesture.up();
  // The first frame after a pointer goes up is where the release animations
  // start their clock, so nothing has moved yet.
  await tester.pump();
}

void main() {
  testWidgets('the note is halfway into the dock', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    await _dropOnDelete(tester);
    await pumpMs(tester, 150);
    await capture(tester, 'release__t0150');

    await tester.pumpAndSettle();
  });

  testWidgets('the list has closed over the removed note', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    await _dropOnDelete(tester);
    await tester.pumpAndSettle();
    await capture(tester, 'release__settled');
  });

  testWidgets('dropping a note on an action removes it and reflows the list', (
    tester,
  ) async {
    await pumpScreen(tester, const App());
    await tester.pump();
    final second = tester.getRect(find.byType(StickyNote).at(1));

    await _dropOnDelete(tester);
    expect(
      find.byType(StickyNote),
      findsNWidgets(kNotes.length),
      reason: 'the note only leaves the list once its travel finishes',
    );

    await pumpMs(
      tester,
      kRemovalShrinkDelay.inMilliseconds +
          kRemovalShrinkDuration.inMilliseconds +
          20,
    );
    await tester.pump();
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length - 1));
    expect(find.byType(ActionDock), findsNothing);
    expect(
      find.text('Useful hints to build a perfect design for iPhone Xs'),
      findsNothing,
    );

    final midReflow = tester.getRect(find.byType(StickyNote).at(0));
    expect(
      midReflow.top,
      greaterThan(171.25),
      reason: 'the list is still springing the gap closed',
    );

    await tester.pumpAndSettle();
    final settled = tester.getRect(find.byType(StickyNote).at(0));
    expect(settled.top, closeTo(171.25, 0.5));
    expect(settled.height, closeTo(second.height, 0.5));
  });

  testWidgets('a second note peels after the first is gone', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    await _dropOnDelete(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length - 1));

    final gesture = await liftNote(tester, 0);
    expect(find.byType(ActionDock), findsOneWidget);
    await capture(tester, 'release__second_peel');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length - 1));
  });
}
