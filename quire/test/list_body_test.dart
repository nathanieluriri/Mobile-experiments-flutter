import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/screens/desk/list_body.dart';
import 'package:quire/theme/colors.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/dissolve/dissolve_scope.dart';

import 'desk_test.dart' show deskStore;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// The body on the app's ground, under the safe area.
///
/// The bar, the tabs and the sort row are the shell's and are not drawn here:
/// what these goldens judge is the body alone, in the room the shell leaves
/// it. [entries] is a notifier rather than a list so a test can hand the body
/// a different order without rebuilding the app around it, which is exactly
/// what a sort does.
Widget bodyApp(
  ValueListenable<List<LibraryEntry>> entries,
  Widget Function(List<LibraryEntry> entries) build,
) =>
    App(
      routes: <String, WidgetBuilder>{
        kDeskRoute: (context) => ColoredBox(
              color: AppColors.ground,
              child: Padding(
                padding: const EdgeInsets.only(top: kSafeTop),
                child: ValueListenableBuilder<List<LibraryEntry>>(
                  valueListenable: entries,
                  builder: (context, shown, _) => build(shown),
                ),
              ),
            ),
      },
    );

/// Every run the scope has in flight.
List<Object> jobsIn(WidgetTester tester) =>
    DissolveScope.of(tester.element(find.byType(DeskListBody))).jobs;

void main() {
  test('a row says what the document is made of, in its own terms', () async {
    final library = await deskStore();
    final guide = entryFor(kFieldGuide);
    expect(rowMeta(guide, library.peek(guide)), 'PDF - 6 pages - 306 KB');

    final rows = entryFor(kSubscribers);
    expect(rowMeta(rows, library.peek(rows)), 'CSV - 71 rows - 6 KB');

    // Nothing has read this one, so the row claims no count rather than
    // printing a zero it would have to take back.
    expect(rowMeta(entryFor(kPressLease), null), 'PDF - 20 KB');
  });

  testWidgets('the list lays out six rows, ruled under their titles',
      (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => DeskListBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    expect(find.byType(DocumentRow), findsNWidgets(6));
    final first = tester.getRect(find.byType(DocumentRow).first);
    expect(first.height, kListRowHeight);
    expect(first.top, kSafeTop);

    // The rule starts under the title and stops at the row's own padding, so
    // a column of them is a list and not a set of underscores running off the
    // right of the screen.
    final rule = tester.getRect(
      find
          .descendant(
            of: find.byType(DocumentRow).first,
            matching: find.byType(ColoredBox),
          )
          .last,
    );
    expect(rule.left, kListRuleInset);
    expect(rule.right, first.right - kListRowPaddingX);
    expect(rule.bottom, first.bottom);
  });

  testWidgets('sorting the list moves the rows and takes nothing apart',
      (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => DeskListBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    // A sort, then a filter. Both change which rows are on screen and neither
    // takes a document off the desk, so nothing comes apart. A list that
    // disintegrated every time it was sorted would be a list nobody trusts.
    entries.value = library.visible.reversed.toList();
    await settle(tester);
    expect(jobsIn(tester), isEmpty);
    expect(find.byType(DocumentRow), findsNWidgets(6));

    entries.value = <LibraryEntry>[
      for (final entry in library.visible)
        if (entry.format == DocFormat.pdf) entry,
    ];
    await settle(tester);
    expect(jobsIn(tester), isEmpty);
    expect(find.byType(DocumentRow), findsNWidgets(2));

    entries.value = library.visible;
    await settle(tester);
    expect(jobsIn(tester), isEmpty);
  });

  testWidgets('a document leaving the desk comes apart and the gap closes',
      (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => DeskListBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    final removed = entryFor(kPressLease);
    final before = tester.getRect(find.byType(DocumentRow).at(2)).top;
    library.remove(removed);
    entries.value = library.visible;
    await tester.pump();
    expect(jobsIn(tester), hasLength(1));

    // The row keeps its slot for as long as its own pixels are in the air.
    // A gap closing under falling dust is the list moving on before the
    // document has finished leaving.
    await pumpMs(tester, 60);
    expect(tester.getRect(find.byType(DocumentRow).at(2)).top, before);
    await pumpMs(tester, kDissolve.inMilliseconds ~/ 2);
    expect(tester.getRect(find.byType(DocumentRow).at(2)).top, before);

    // Once the dust has landed the slot closes, on the layout spring, so the
    // row under it travels rather than jumping.
    for (var waited = 0; waited < 4000 && jobsIn(tester).isNotEmpty; waited += 60) {
      await pumpMs(tester, 60);
    }
    expect(jobsIn(tester), isEmpty);
    expect(tester.getRect(find.byType(DocumentRow).at(2)).top, before);
    await pumpMs(tester, 60);
    final travelling = tester.getRect(find.byType(DocumentRow).at(2)).top;
    expect(travelling, lessThan(before));
    expect(travelling, greaterThan(before - kListRowHeight));

    await settle(tester);
    expect(find.byType(DocumentRow), findsNWidgets(5));
    expect(
      tester.getRect(find.byType(DocumentRow).at(1)).top,
      before - kListRowHeight,
    );
  });

  testWidgets('a document that has been read carries how far', (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => DeskListBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    final read = library.entries.where((entry) {
      final store = library.peek(entry);
      return store != null && store.opened;
    });
    expect(read, isNotEmpty);
    final tracks = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox &&
          widget.width == kListProgressWidth &&
          widget.height == kListProgressHeight,
    );
    expect(tracks, findsNWidgets(read.length));
  });
}
