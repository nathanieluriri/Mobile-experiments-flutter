import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/note_store.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/screens/notes/compose_sheet.dart';
import 'package:sticky_note_peel/screens/notes/notes_drawer.dart';
import 'package:sticky_note_peel/widgets/press_fade.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';

Future<NoteStore> pumpNotes(WidgetTester tester) async {
  final store = NoteStore();
  await pumpScreen(tester, App(store: store));
  await tester.pump();
  return store;
}

Future<void> openCompose(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.pen));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, int field, String text) async {
  await tester.enterText(find.byType(EditableText).at(field), text);
  await tester.pumpAndSettle();
}

/// The colours a new note can be written on, in the order they are offered.
Finder swatches() => find.descendant(
      of: find.byType(ComposeSheet),
      matching: find.byWidgetPredicate(
        (widget) => widget is PressFade && widget.semanticLabel == 'Paper colour',
      ),
    );

/// The fields on the sheet, in the order they are written.
const _title = 0;
const _text = 1;
const _tag = 2;

void main() {
  testWidgets('the button opens a blank sheet', (tester) async {
    await pumpNotes(tester);
    expect(find.byType(ComposeSheet), findsNothing);

    await openCompose(tester);
    expect(find.byType(ComposeSheet), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Write something'), findsOneWidget);
    expect(find.text('Add to a list'), findsOneWidget);
    expect(find.text('Note'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);
  });

  testWidgets('a blank sheet', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await capture(tester, 'compose__empty');
  });

  testWidgets('a sheet being written on', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, _title, 'Things to fix on the bike');
    await fill(tester, _text, 'The chain skips under load and the rear brake '
        'has gone soft again.');
    await fill(tester, _tag, 'Repairs');
    await capture(tester, 'compose__filled');
  });

  testWidgets('writing a note puts it at the top of the list', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);

    await fill(tester, _title, 'Buy a new lock');
    await fill(tester, _text, 'The old one sticks in the rain.');
    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeSheet), findsNothing);
    expect(store.notes, hasLength(kNotes.length + 1));
    expect(store.notes.first.title, 'Buy a new lock');
    expect(store.notes.first.body, 'The old one sticks in the rain.');
    expect(store.notes.first.checklist, isNull);
    expect(findText('Buy a new lock'), findsOneWidget);

    final first = tester.getRect(find.byType(StickyNote).at(0));
    expect(first.top, closeTo(171.25, 0.5), reason: 'it took the top slot');
  });

  testWidgets('a list becomes a checklist, one item per line', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);

    await fill(tester, _title, 'Camping');
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await fill(tester, _text, 'Tent\n\nSleeping bag\n  Stove  \n');
    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pumpAndSettle();

    expect(store.notes.first.checklist, ['Tent', 'Sleeping bag', 'Stove']);
    expect(store.notes.first.body, isNull);
  });

  testWidgets('a note written into a list joins that list', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);

    await fill(tester, _title, 'Sharpen the chisels');
    await fill(tester, _tag, 'Workshop');
    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pumpAndSettle();

    expect(store.notes.first.tags, ['Workshop']);
    expect(store.tagCounts['Workshop'], 1);

    await tester.tap(find.byIcon(LucideIcons.menu));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(NotesDrawer),
        matching: find.text('Workshop'),
      ),
      findsOneWidget,
      reason: 'a new list shows up in the drawer on its own',
    );
  });

  testWidgets('a sheet with no title cannot be saved', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);

    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pumpAndSettle();

    expect(store.notes, hasLength(kNotes.length));
    expect(find.byType(ComposeSheet), findsOneWidget, reason: 'still open');
  });

  testWidgets('discarding a sheet keeps the list as it was', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, _title, 'Never mind');

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeSheet), findsNothing);
    expect(store.notes, hasLength(kNotes.length));
  });

  testWidgets('the paper can be a different colour', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);

    await fill(tester, _title, 'Pink');
    expect(swatches(), findsNWidgets(kComposeColors.length));
    await tester.tap(swatches().at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.check));
    await tester.pumpAndSettle();

    expect(store.notes.first.color, kComposeColors[3]);
  });
}
