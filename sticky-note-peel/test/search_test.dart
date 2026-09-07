import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sticky_note_peel/app.dart';
import 'package:sticky_note_peel/data/note_store.dart';
import 'package:sticky_note_peel/data/notes.dart';
import 'package:sticky_note_peel/widgets/marked_text.dart';
import 'package:sticky_note_peel/widgets/sticky_note.dart';

import 'support/golden.dart';

Future<NoteStore> pumpNotes(WidgetTester tester) async {
  final store = NoteStore();
  await pumpScreen(tester, App(store: store));
  await tester.pump();
  return store;
}

Future<void> openSearch(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.search));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pumpAndSettle();
}

/// Every line on a note that is carrying a marker for [query].
Iterable<MarkedText> marked(WidgetTester tester, String query) {
  return tester
      .widgetList<MarkedText>(find.byType(MarkedText))
      .where((line) => line.query == query && line.text.toLowerCase()
          .contains(query.toLowerCase()));
}

void main() {
  testWidgets('the magnifier grows into a field', (tester) async {
    await pumpNotes(tester);
    expect(find.byType(EditableText), findsNothing);

    await openSearch(tester);
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text('Search notes'), findsOneWidget);
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    expect(
      find.byIcon(LucideIcons.menu),
      findsOneWidget,
      reason: 'the menu is still built, just faded out of the way',
    );
  });

  testWidgets('the search field is open', (tester) async {
    await pumpNotes(tester);
    await openSearch(tester);
    await capture(tester, 'search__open');
  });

  testWidgets('typing narrows the list as you go', (tester) async {
    final store = await pumpNotes(tester);
    await openSearch(tester);

    await type(tester, 'sweater');
    expect(store.query, 'sweater');
    expect(find.byType(StickyNote), findsOneWidget);
    expect(findText('Europe travel packing list'), findsOneWidget);

    await type(tester, 'design');
    expect(
      find.byType(StickyNote),
      findsNWidgets(2),
      reason: 'the design note, and the one about a designer',
    );

    await type(tester, 'zzz');
    expect(find.byType(StickyNote), findsNothing);
    expect(find.text('Nothing matches "zzz"'), findsOneWidget);
  });

  testWidgets('a search that finds nothing', (tester) async {
    await pumpNotes(tester);
    await openSearch(tester);
    await type(tester, 'zzz');
    await capture(tester, 'search__empty');
  });

  testWidgets('an empty list says so rather than showing a blank page',
      (tester) async {
    final store = await pumpNotes(tester);
    store.remove('travel');
    store.setTagFilter('Design');
    await tester.pumpAndSettle();
    expect(find.byType(StickyNote), findsOneWidget);

    store.remove('design');
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsNothing);
  });

  testWidgets('what was found is marked on the note', (tester) async {
    await pumpNotes(tester);
    await openSearch(tester);
    await type(tester, 'packing');

    final hits = marked(tester, 'packing');
    expect(hits, isNotEmpty);
    expect(
      hits.map((line) => line.text),
      contains('Europe travel packing list'),
    );
  });

  testWidgets('a search with matches marked', (tester) async {
    await pumpNotes(tester);
    await openSearch(tester);
    await type(tester, 'design');
    await capture(tester, 'search__matches');
  });

  testWidgets('closing the search clears it and brings every note back',
      (tester) async {
    final store = await pumpNotes(tester);
    await openSearch(tester);
    await type(tester, 'sweater');
    expect(find.byType(StickyNote), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();

    expect(store.query, isEmpty);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(StickyNote), findsNWidgets(kNotes.length));
  });

  testWidgets('a search inside a list looks in that list only', (tester) async {
    final store = await pumpNotes(tester);
    store.setTagFilter('Travel');
    await tester.pumpAndSettle();

    await openSearch(tester);
    await type(tester, 'wake');
    expect(
      find.byType(StickyNote),
      findsNothing,
      reason: 'the note that matches is not in this list',
    );
  });

  testWidgets('the title makes way for the field', (tester) async {
    await pumpNotes(tester);
    final before = tester.getRect(find.byType(StickyNote).at(0));

    await openSearch(tester);
    final after = tester.getRect(find.byType(StickyNote).at(0));
    expect(
      after.top,
      lessThan(before.top),
      reason: 'the heading folds away and the notes move up into its place',
    );
  });
}
