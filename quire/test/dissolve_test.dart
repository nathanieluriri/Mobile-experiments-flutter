import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_empty.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/screens/desk/search_pill.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/dissolve/dissolve_scope.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// Every run the scope has in flight.
List<Object> jobsIn(WidgetTester tester) =>
    DissolveScope.of(tester.element(find.byType(DeskScreen))).jobs;

/// Where row [index] sits in the body, under the shell's own chrome.
Rect rowRect(int index) => Rect.fromLTWH(
  0,
  kSafeTop +
      kTopBarHeight +
      kTabStripHeight +
      kSortRowHeight +
      kListRowHeight * index,
  kScreenWidth,
  kListRowHeight,
);

/// The middle of row [index]'s overflow target.
Offset overflowOf(int index) {
  final rect = rowRect(index);
  return Offset(
    rect.right - kListRowPaddingX - kOverflowTarget / 2,
    rect.center.dy,
  );
}

/// Takes row [index] off the desk through its own overflow menu.
Future<void> removeRow(WidgetTester tester, int index) async {
  // Found rather than measured: the dots move with the row, and a tap worked
  // out from constants goes on hitting where the row used to be.
  await tester.tap(find.byType(OverflowTarget).at(index));
  await tester.pump();
  await pumpMs(tester, kSortMenuIn.inMilliseconds);
  // The pills peel off the dots one at a time, so the one we want is not
  // under the finger until its own neck has let go.
  for (
    var waited = 0;
    waited < 2000 && find.text('Remove').hitTestable().evaluate().isEmpty;
    waited += 60
  ) {
    await pumpMs(tester, 60);
  }
  await tester.tap(find.text('Remove'));
  // The row is put back whole for one frame, so the snapshot the dust is made
  // of is a snapshot of a row and not of a half pressed one.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a removed row comes apart, and undo gathers it back', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final removed = entryFor(kPressLease);
    await removeRow(tester, 1);
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

    // The document is back on the desk but not yet on the page: its slot is
    // opening and a run is gathering its dust into it. A gap that opened with
    // no run behind it would be the undo of a removal that never came apart.
    await pumpMs(tester, 600);
    expect(jobsIn(tester), hasLength(1));
    expect(documentTitled('Press Lease').hitTestable(), findsNothing);
    await capture(tester, 'materialize__t0600');

    await settle(tester);
    expect(jobsIn(tester), isEmpty);
    expect(documentTitled('Press Lease'), findsOneWidget);
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
    await tester.tapAt(rowRect(0).center);
    await settle(tester);
    expect(opened, 1);
    expect(jobsIn(tester), isEmpty);

    await tester.tap(find.byType(SearchPill));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'es');
    await settle(tester);
    expect(store.visible.length, 3);
    expect(jobsIn(tester), isEmpty);
  });

  testWidgets('the pill runs out on its own and the removal stands', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await removeRow(tester, 1);
    expect(jobsIn(tester), hasLength(1));

    await pumpMs(tester, 4000);
    await settle(tester);
    expect(find.text('UNDO'), findsNothing);
    expect(store.lastRemoved, isNull);
    expect(store.entries.length, 5);
  });

  testWidgets('every document leaving at once comes apart, the last one too', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    // Six runs, all in the air together. Each one paints the pixels the list
    // photographed, and the list must go on holding every one of those until
    // its own run has landed.
    for (final entry in libraryEntries) {
      store.remove(entry);
    }
    await tester.pump();
    expect(jobsIn(tester), hasLength(libraryEntries.length));

    // The sixth removal empties the desk, which puts the empty state where the
    // list was. The dust of that last row is painted by the scope above and
    // outlives the list it came off, so the run finishes rather than losing
    // its picture half way through.
    await settle(tester);
    expect(jobsIn(tester), isEmpty);
    expect(store.entries, isEmpty);
    expect(find.byType(DocumentRow), findsNothing);
    expect(find.byType(DeskEmpty), findsOneWidget);
  });

  testWidgets('a bin filled in an earlier run does not come apart again', (
    tester,
  ) async {
    final binned = entryFor(kPressLease).path;
    final store = LibraryStore(
      catalogue: SavedDesk(<String, Object?>{
        'binned': <Object?>[binned],
      }),
    );
    await pumpScreen(tester, deskApp(store));
    await settle(tester);
    // The first frame is the shipped manifest alone: reading the phone takes
    // longer than a frame, so everything is on the desk for that one frame.
    expect(documentTitled('Press Lease'), findsOneWidget);

    await store.boot(parse: false);
    await settle(tester);

    // It goes, because it was in the bin before the app opened. It does not
    // come apart, because it was never on the desk to leave it.
    expect(documentTitled('Press Lease'), findsNothing);
    expect(store.binned.map((entry) => entry.fileName), contains(kPressLease));
    expect(jobsIn(tester), isEmpty);
  });

  test('a desk says when it has read what it holds', () async {
    // Until then the desk is the shipped manifest and nothing else, and what
    // that read takes off it was never on it.
    final store = LibraryStore(catalogue: SavedDesk(<String, Object?>{}));
    expect(store.booted, isFalse);
    await store.boot(parse: false);
    expect(store.booted, isTrue);
  });

  test('a desk with nowhere to read from holds everything at once', () {
    expect(LibraryStore().booted, isTrue);
  });
}
