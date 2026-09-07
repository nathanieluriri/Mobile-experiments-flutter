import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/note_store.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/screens/notes/notes_drawer.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';

Future<NoteStore> pumpNotes(WidgetTester tester) async {
  final store = NoteStore();
  await pumpScreen(tester, App(store: store));
  await tester.pump();
  return store;
}

/// A row inside the panel, as opposed to the same word on a note's chip.
Finder drawerRow(String label) => find.descendant(
      of: find.byType(NotesDrawer),
      matching: find.text(label),
    );

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.menu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the drawer holds one row per list, plus everything',
      (tester) async {
    await pumpNotes(tester);
    expect(find.byType(NotesDrawer), findsNothing);

    await openDrawer(tester);
    expect(find.byType(NotesDrawer), findsOneWidget);
    expect(drawerRow('All notes'), findsOneWidget);
    expect(drawerRow('Lists'), findsOneWidget);
    for (final tag in ['Design', 'Travel', 'Things to do', 'Article']) {
      expect(drawerRow(tag), findsOneWidget, reason: 'a row for $tag');
    }
  });

  testWidgets('the drawer is open', (tester) async {
    await pumpNotes(tester);
    await openDrawer(tester);
    await capture(tester, 'drawer__open');
  });

  testWidgets('picking a list narrows the notes and renames the title',
      (tester) async {
    final store = await pumpNotes(tester);
    await openDrawer(tester);

    await tester.tap(drawerRow('Travel'));
    await tester.pumpAndSettle();

    expect(store.tagFilter, 'Travel');
    expect(find.byType(NotesDrawer), findsNothing, reason: 'it closes behind');
    expect(find.byType(StickyNote), findsOneWidget);
    expect(find.text('Europe travel packing list'), findsOneWidget);
    expect(
      find.text('Travel'),
      findsNWidgets(3),
      reason: 'the heading over the list, the header echo of it, and the chip '
          'on the note it kept',
    );
  });

  testWidgets('a filtered list', (tester) async {
    final store = await pumpNotes(tester);
    store.setTagFilter('Travel');
    await tester.pumpAndSettle();
    await capture(tester, 'notes__filtered');
  });

  testWidgets('notes leave through their own slot, not all at once',
      (tester) async {
    final store = await pumpNotes(tester);
    final before = tester.getRect(find.byType(StickyNote).at(1));

    store.setTagFilter('Travel');
    await pumpMs(tester, 0);
    await pumpMs(tester, 80);

    expect(
      find.byType(StickyNote),
      findsNWidgets(kNotes.length),
      reason: 'the notes on their way out are still drawn',
    );
    final during = tester.getRect(find.byType(StickyNote).at(1));
    expect(
      during.top,
      lessThan(before.top),
      reason: 'the note that stays is sliding up as the slots above it close',
    );

    await tester.pumpAndSettle();
    expect(find.byType(StickyNote), findsOneWidget);
  });

  testWidgets('going back to everything brings the notes back', (tester) async {
    final store = await pumpNotes(tester);
    store.setTagFilter('Travel');
    await tester.pumpAndSettle();
    expect(find.byType(StickyNote), findsOneWidget);

    await openDrawer(tester);
    await tester.tap(drawerRow('All notes'));
    await tester.pumpAndSettle();

    expect(store.tagFilter, isNull);
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length));
  });

  testWidgets('tapping the dimmed list closes the drawer', (tester) async {
    await pumpNotes(tester);
    await openDrawer(tester);

    await tester.tapAt(const Offset(380, 700));
    await tester.pumpAndSettle();
    expect(find.byType(NotesDrawer), findsNothing);
  });

  testWidgets('dragging the panel off the left edge closes it', (tester) async {
    await pumpNotes(tester);
    await openDrawer(tester);

    await tester.drag(find.byType(NotesDrawer), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.byType(NotesDrawer), findsNothing);
  });

  testWidgets('a list disappears when its last note is deleted',
      (tester) async {
    final store = await pumpNotes(tester);
    store.remove('travel');
    await tester.pumpAndSettle();

    await openDrawer(tester);
    expect(drawerRow('Travel'), findsNothing);
    expect(drawerRow('Design'), findsOneWidget);
  });
}
