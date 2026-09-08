import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/card_peel.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/action_dock.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/golden.dart';

/// Where card [index] sits on the desk, in screen coordinates.
Rect cardRect(int index) => Rect.fromLTWH(
      kScreenPadding,
      kCardListTop + (kCardHeight + kCardGap) * index,
      kCardWidth,
      kCardHeight,
    );

/// The middle of card [index]'s bottom right peel handle.
Offset handleOf(int index) {
  final rect = cardRect(index);
  return Offset(
    rect.right - kCornerHandle / 2,
    rect.bottom - kCornerHandle / 2,
  );
}

/// A point inside card [index], given in the card's own coordinates.
Offset inCard(int index, Offset local) => cardRect(index).topLeft + local;

/// Where dock target [action] sits under card [index].
Offset dockTargetOf(int index, DeskAction action) => inCard(
      index,
      Offset(
        dockButtonCenterX(
          kDeskActions.indexOf(action),
          kCardWidth,
          kDeskActions.length,
        ),
        dockRowCenterY(kCardHeight),
      ),
    );

/// Arms the peel on card [index] and starts a drag, leaving the finger down.
Future<TestGesture> beginPeel(WidgetTester tester, int index) async {
  final gesture = await tester.startGesture(handleOf(index));
  await tester.pump(kPeelLongPress + const Duration(milliseconds: 20));
  await gesture.moveBy(const Offset(-6, -6));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('the corner folds under a finger and the dock rises',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    // press-lease.pdf, the second card, so the back layer has a short file
    // name and a real page count to show.
    final gesture = await beginPeel(tester, 1);
    await capture(tester, 'peel__t0000');

    // Far enough that the fold has uncovered the half of the sheet its own
    // corner is in, which is where the back's detail is set.
    await gesture.moveTo(inCard(1, const Offset(30, 20)));
    await tester.pump();
    await pumpMs(tester, 300);
    await capture(tester, 'peel__t0300');

    await settle(tester);
    await capture(tester, 'desk__card_peeled');
    await gesture.cancel();
    await settle(tester);
  });

  testWidgets('a target under the drag point grows and names itself',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final gesture = await beginPeel(tester, 1);
    final target = dockTargetOf(1, DeskAction.remove);
    // The first move brings the dock up; the second aims at it, which is what
    // a finger travelling towards a target does anyway.
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await settle(tester);

    expect(find.text('REMOVE'), findsOneWidget);
    await capture(tester, 'desk__dock_hover');
    await gesture.cancel();
    await settle(tester);
  });

  testWidgets('SIGN refuses anything that is not a page file', (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    // subscribers.csv, the fifth card. Nothing can be signed but a PDF.
    final gesture = await beginPeel(tester, 4);
    await gesture.moveBy(const Offset(-94, -34));
    await tester.pump();
    await settle(tester);

    final dock = tester.widget<ActionDock>(find.byType(ActionDock));
    expect(dock.actions.length, kDeskActions.length);
    expect(dock.actions[kDeskActions.indexOf(DeskAction.read)].enabled, isTrue);
    expect(
      dock.actions[kDeskActions.indexOf(DeskAction.sign)].enabled,
      isFalse,
    );

    // The card refuses the drop: the desk keeps every document and the dock
    // leaves, rather than the card going anywhere.
    final before = tester.getTopLeft(find.byType(CardPeel).at(4));
    await gesture.moveTo(dockTargetOf(4, DeskAction.sign));
    await tester.pump();
    await gesture.up();
    await settle(tester);
    expect(store.entries.length, 6);
    expect(find.byType(ActionDock), findsNothing);
    expect(tester.getTopLeft(find.byType(CardPeel).at(4)), before);
  });
}
