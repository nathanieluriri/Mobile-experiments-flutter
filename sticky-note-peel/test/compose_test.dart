import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/note_store.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/screens/notes/compose_actions.dart';
import 'package:sticky_note_peel/screens/notes/compose_sheet.dart';
import 'package:sticky_note_peel/screens/notes/notes_drawer.dart';
import 'package:sticky_note_peel/screens/notes/notes_screen.dart';
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

/// A button the sheet offers, by what it says it does.
Finder sheetButton(String label) => find.descendant(
      of: find.byType(ComposeSheet),
      matching: find.byWidgetPredicate(
        (widget) => widget is PressFade && widget.semanticLabel == label,
      ),
    );

Future<void> reveal(WidgetTester tester) async {
  await tester.tap(sheetButton('Add to this note'));
  await tester.pumpAndSettle();
}

Future<void> act(WidgetTester tester, ComposeAction action) async {
  await tester.tap(sheetButton(action.label));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(sheetButton('Save note'));
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, Finder field, String text) async {
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Finder fields() =>
    find.descendant(of: find.byType(ComposeSheet), matching: find.byType(EditableText));

void main() {
  testWidgets('a blank sheet offers a title, a line to write on, and a plus',
      (tester) async {
    await pumpNotes(tester);
    expect(find.byType(ComposeSheet), findsNothing);

    await openCompose(tester);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Just start writing'), findsOneWidget);
    expect(sheetButton('Add to this note'), findsOneWidget);
    for (final action in ComposeAction.values) {
      expect(
        sheetButton(action.label),
        findsNothing,
        reason: '${action.label} waits behind the plus',
      );
    }
  });

  testWidgets('a blank sheet', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await capture(tester, 'compose__empty');
  });

  testWidgets('the plus opens into everything a note can hold', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await reveal(tester);

    for (final action in ComposeAction.values) {
      expect(sheetButton(action.label), findsOneWidget);
    }
    expect(sheetButton('Close'), findsOneWidget, reason: 'the plus is now a cross');
  });

  testWidgets('the actions are out', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await reveal(tester);
    await capture(tester, 'compose__actions');
  });

  testWidgets('a to-do adds a row, and return adds the next one',
      (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Camping');

    await reveal(tester);
    await act(tester, ComposeAction.todo);
    expect(fields(), findsNWidgets(3), reason: 'title, body, one to-do');

    await fill(tester, fields().at(2), 'Tent');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(fields(), findsNWidgets(4));

    await fill(tester, fields().at(3), 'Stove');
    await save(tester);

    expect(store.notes.first.checklist, ['Tent', 'Stove']);
    expect(store.notes.first.body, isNull);
  });

  testWidgets('a to-do row with nothing on it goes away on backspace',
      (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await reveal(tester);
    await act(tester, ComposeAction.todo);
    await act(tester, ComposeAction.todo);
    expect(fields(), findsNWidgets(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(fields(), findsNWidgets(3));
  });

  testWidgets('a sheet being written on', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Things to fix on the bike');
    await fill(
      tester,
      fields().at(1),
      'The chain skips under load and the rear brake has gone soft again.',
    );
    await reveal(tester);
    await act(tester, ComposeAction.tag);
    await fill(tester, fields().last, 'Repairs');
    await act(tester, ComposeAction.paper);
    await capture(tester, 'compose__filled');
  });

  testWidgets('a saved note flies to the place the list made for it',
      (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Buy a new lock');
    await fill(tester, fields().at(1), 'The old one sticks in the rain.');

    final sheet = tester.getRect(find.byType(ComposeSheet));
    await tester.tap(sheetButton('Save note'));
    await tester.pump();
    await tester.pump();

    final start = tester.getRect(find.byKey(kLandingNote));
    expect(
      start.top,
      closeTo(sheet.top, 2),
      reason: 'it sets off from where it was written',
    );

    await pumpMs(tester, 500);
    await tester.pumpAndSettle();
    expect(find.byKey(kLandingNote), findsNothing);

    final landed = tester.getRect(find.byType(StickyNote).at(0));
    expect(landed.top, closeTo(171.25, 0.5));
    expect(store.notes.first.title, 'Buy a new lock');
    expect(findText('Buy a new lock'), findsOneWidget);
  });

  testWidgets('the sheet travels, it does not cut', (tester) async {
    await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Somewhere to land');

    await tester.tap(sheetButton('Save note'));
    await tester.pump();
    await tester.pump();
    final start = tester.getRect(find.byKey(kLandingNote));

    await pumpMs(tester, 90);
    final middle = tester.getRect(find.byKey(kLandingNote));
    await pumpMs(tester, 90);
    final later = tester.getRect(find.byKey(kLandingNote));

    // The sheet is written above where the note will sit, so it travels down
    // into its slot rather than jumping there.
    expect(middle.top, greaterThan(start.top));
    expect(later.top, greaterThan(middle.top));
    expect(
      later.height,
      lessThan(start.height),
      reason: 'it takes the size of the note as well as its place',
    );

    await tester.pumpAndSettle();
    expect(find.byKey(kLandingNote), findsNothing);
  });

  testWidgets('tapping a note opens it with what is already on it',
      (tester) async {
    final store = await pumpNotes(tester);
    await tester.tap(
      findText('Useful hints to build a perfect design for iPhone Xs'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ComposeSheet), findsOneWidget);
    final sheet = tester.widget<ComposeSheet>(find.byType(ComposeSheet));
    expect(sheet.initial?.id, 'design');
    expect(
      fields(),
      findsNWidgets(3),
      reason: 'title, body, and the list it is already in',
    );

    await fill(tester, fields().at(0), 'Hints for a perfect design');
    await save(tester);

    expect(
      store.notes,
      hasLength(kNotes.length),
      reason: 'editing changes a note, it does not add one',
    );
    final edited = store.notes.firstWhere((note) => note.id == 'design');
    expect(edited.title, 'Hints for a perfect design');
    expect(edited.tags, ['Design'], reason: 'it stayed in its list');
  });

  testWidgets('an edited list keeps the rows it had', (tester) async {
    final store = await pumpNotes(tester);
    await tester.tap(findText('Weekend checklist'));
    await tester.pumpAndSettle();

    final before = kNotes.firstWhere((note) => note.id == 'weekend');
    expect(fields(), findsNWidgets(2 + before.checklist!.length + 1));

    await fill(tester, fields().at(2), 'Call mom, dad and gran');
    await save(tester);

    final after = store.notes.firstWhere((note) => note.id == 'weekend');
    expect(after.checklist!.first, 'Call mom, dad and gran');
    expect(after.checklist, hasLength(before.checklist!.length));
  });

  testWidgets('a note written into a list joins that list', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Sharpen the chisels');
    await reveal(tester);
    await act(tester, ComposeAction.tag);
    await fill(tester, fields().last, 'Workshop');
    await save(tester);

    expect(store.notes.first.tags, ['Workshop']);

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

  testWidgets('the paper can be a different colour', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Pink');

    await reveal(tester);
    await act(tester, ComposeAction.paper);
    expect(sheetButton('Paper colour'), findsNWidgets(kComposeColors.length));
    await tester.tap(sheetButton('Paper colour').at(3));
    await tester.pumpAndSettle();
    await save(tester);

    expect(store.notes.first.color, kComposeColors[3]);
  });

  testWidgets('a sheet with no title cannot be saved', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await save(tester);

    expect(store.notes, hasLength(kNotes.length));
    expect(find.byType(ComposeSheet), findsOneWidget, reason: 'still open');
  });

  testWidgets('discarding a sheet keeps the list as it was', (tester) async {
    final store = await pumpNotes(tester);
    await openCompose(tester);
    await fill(tester, fields().at(0), 'Never mind');

    await tester.tap(sheetButton('Discard'));
    await tester.pumpAndSettle();

    expect(find.byType(ComposeSheet), findsNothing);
    expect(store.notes, hasLength(kNotes.length));
  });
}
