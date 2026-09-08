import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:quire/screens/desk/card_peel.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/dissolve/dissolve_scope.dart';

import 'card_peel_test.dart' show beginPeel, cardRect, dockTargetOf;
import 'desk_test.dart' show deskApp, deskStore;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// Every run the scope has in flight.
List<Object> jobsIn(WidgetTester tester) =>
    DissolveScope.of(tester.element(find.byType(DeskScreen))).jobs;

/// Peels card [index] onto REMOVE and lets go.
///
/// Two moves rather than one, because the dock has to be on screen before a
/// target under the drag point can know it is the one being aimed at.
Future<void> dropOnRemove(WidgetTester tester, int index) async {
  final gesture = await beginPeel(tester, index);
  final target = dockTargetOf(index, DeskAction.remove);
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump();
  await settle(tester);
  await gesture.up();
  // The card is put back whole for one frame, so the snapshot the dust is made
  // of is a snapshot of a card and not of a peeled one.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a removed card comes apart, and undo gathers it back',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final removed = entryFor(kPressLease);
    await dropOnRemove(tester, 1);
    final left = store.entries.map((entry) => entry.fileName);
    expect(left, isNot(contains(kPressLease)));
    expect(store.lastRemoved, removed);
    await capture(tester, 'dissolve__t0000');

    await pumpMs(tester, 1200);
    await capture(tester, 'dissolve__t1200');

    await pumpMs(tester, 1600);
    await capture(tester, 'dissolve__t2800');

    // The run is over and the pill still has most of a second left on it.
    await pumpMs(tester, 400);
    expect(find.text('Removed Press Lease'), findsOneWidget);
    await capture(tester, 'desk__undo_pill');

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    await tester.pump();
    expect(store.entries.map((entry) => entry.fileName), contains(kPressLease));

    await pumpMs(tester, 600);
    await capture(tester, 'materialize__t0600');
    await settle(tester);
  });

  testWidgets('nothing else on the desk comes apart', (tester) async {
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    final store = await deskStore();
    var opened = 0;
    await pumpScreen(
      tester,
      deskApp(store, onOpen: (entry, cardRect) => opened++),
    );
    await settle(tester);

    // Opening a document is not a structure coming apart, and neither is a
    // search, a filter, or a card leaving the result set. The dissolve earns
    // its keep only where something is genuinely lost or gained.
    await tester.tapAt(cardRect(0).center);
    await settle(tester);
    expect(opened, 1);
    expect(jobsIn(tester), isEmpty);

    await tester.tap(find.byIcon(LucideIcons.search));
    await tester.pump();
    await pumpMs(tester, kSearchOpen.inMilliseconds);
    await tester.enterText(find.byType(EditableText), 'es');
    await settle(tester);
    expect(store.visible.length, 3);
    expect(jobsIn(tester), isEmpty);
  });

  testWidgets('the pill runs out on its own and the removal stands',
      (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await dropOnRemove(tester, 1);
    expect(store.retainedSnapshot, isNotNull);

    await pumpMs(tester, 4000);
    await settle(tester);
    expect(find.text('UNDO'), findsNothing);
    expect(store.lastRemoved, isNull);
    expect(store.entries.length, 5);
  });
}
