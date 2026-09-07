import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/note_actions.dart';
import 'package:sticky_note_peel/theme/colors.dart';
import 'package:sticky_note_peel/theme/metrics.dart';
import 'package:sticky_note_peel/widgets/action_dock.dart';

import 'support/golden.dart';
import 'support/peel.dart';

void main() {
  testWidgets('dock under a lifted note', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    await capture(tester, 'dock__lifted');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dock with the archive action hovered', (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    final drag = PeelDrag(tester, gesture, dockButtonCenter(tester, 1));
    await drag.advanceTo(600);
    await pumpMs(tester, 400);
    await capture(tester, 'dock__hover');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the dock carries one button per action, evenly spaced',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    expect(find.byType(DockButton), findsNWidgets(kNoteActions.length));

    final note = tester.getRect(find.byType(ActionDock));
    for (var i = 0; i < kNoteActions.length; i++) {
      final button = tester.getRect(find.byType(DockButton).at(i));
      expect(
        button.center.dx - note.left,
        closeTo(dockButtonCenterX(i, note.width, kNoteActions.length), 0.01),
      );
      expect(button.width, kDockButtonSpacing);
    }

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a hovered button takes its accent colour and shows its label',
      (tester) async {
    await pumpScreen(tester, const App());
    await tester.pump();

    final gesture = await liftNote(tester, 0);
    expect(circleColorOf(tester, 0), AppColors.white);
    expect(labelOpacityOf(tester, 0), 0);

    final drag = PeelDrag(tester, gesture, dockButtonCenter(tester, 0));
    await drag.advanceTo(600);
    await pumpMs(tester, 400);

    expect(circleColorOf(tester, 0), AppColors.danger);
    expect(labelOpacityOf(tester, 0), closeTo(1, 0.001));
    expect(circleColorOf(tester, 1), AppColors.white);
    expect(labelOpacityOf(tester, 1), 0);

    await gesture.up();
    await tester.pumpAndSettle();
  });
}

/// The fill of dock button [index]'s circle.
Color? circleColorOf(WidgetTester tester, int index) {
  final container = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(DockButton).at(index),
      matching: find.byType(Container),
    ),
  ).first;
  return (container.decoration! as BoxDecoration).color;
}

/// How visible dock button [index]'s label is.
double labelOpacityOf(WidgetTester tester, int index) {
  final label = find.descendant(
    of: find.byType(DockButton).at(index),
    matching: find.text(kNoteActions[index].label),
  );
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: label, matching: find.byType(Opacity)),
  );
  return opacities.fold<double>(1, (total, o) => total * o.opacity);
}
