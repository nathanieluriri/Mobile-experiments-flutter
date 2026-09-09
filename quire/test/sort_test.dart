import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/shell_model.dart';
import 'package:quire/screens/desk/sort_menu.dart';
import 'package:quire/screens/desk/sort_row.dart';
import 'package:quire/theme/metrics.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'shell_test.dart' show kTitles, titlesInOrder;
import 'support/golden.dart';

/// The current sort's label, on the left of the sort row.
final Finder sortLabel = find
    .descendant(of: find.byType(SortRow), matching: find.byType(Text))
    .first;

/// Opens the menu from the label, which is what a reader taps.
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(sortLabel);
  await settle(tester);
}

/// One row of the open menu. Scoped to the menu because the sort row prints
/// the current field's label too, and the two must never be confused.
Finder menuRow(String label) =>
    find.descendant(of: find.byType(SortMenu), matching: find.text(label));

/// The rows in the menu carrying a check, in the order the menu lists them.
List<String> checked(WidgetTester tester) {
  final out = <String>[];
  for (final label in <String>[
    ...SortField.values.map((f) => f.label),
    ...SortOrder.values.map((o) => o.label),
  ]) {
    final row =
        find.ancestor(of: menuRow(label), matching: find.byType(Row)).first;
    if (find
        .descendant(of: row, matching: find.byIcon(LucideIcons.check))
        .evaluate()
        .isNotEmpty) {
      out.add(label);
    }
  }
  return out;
}

void main() {
  testWidgets('the menu hangs under the label with one check in each group', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    expect(find.byType(SortMenu), findsNothing);
    await openMenu(tester);

    final menu = tester.getRect(find.byType(SortMenu));
    expect(menu.left, kSortRowPaddingX);
    expect(
      menu.top,
      kSafeTop +
          kTopBarHeight +
          kTabStripHeight +
          kSortRowHeight +
          kSortMenuOffset,
    );
    expect(menu.width, kSortMenuWidth);

    // One answer to each of the two questions, never none and never two.
    expect(checked(tester), <String>['Date modified', 'New to old']);
    await capture(tester, 'sort__menu');
  });

  testWidgets('the menu arrives over 160 ms and leaves on a choice', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    await tester.tap(sortLabel);
    await tester.pump();
    expect(tester.widget<SortMenu>(find.byType(SortMenu)).t, 0);

    await pumpMs(tester, kSortMenuIn.inMilliseconds ~/ 2);
    final half = tester.widget<SortMenu>(find.byType(SortMenu)).t;
    expect(half, greaterThan(0));
    expect(half, lessThan(1));

    await settle(tester);
    expect(tester.widget<SortMenu>(find.byType(SortMenu)).t, 1);

    await tester.tap(menuRow('Size'));
    await settle(tester);
    expect(find.byType(SortMenu), findsNothing);
  });

  testWidgets('each field puts the list in a different order', (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    // The manifest is the order the library was put together in, newest
    // first, so date modified is the list at rest.
    expect(titlesInOrder(tester, kTitles), kTitles);

    await openMenu(tester);
    await tester.tap(menuRow('Name'));
    await settle(tester);
    expect(titlesInOrder(tester, kTitles), <String>[
      'Bindery Notes',
      'Field Guide To Paper',
      'House Style',
      'Press Lease',
      'Press Run Costs',
      'Subscribers',
    ]);

    await openMenu(tester);
    await tester.tap(menuRow('Size'));
    await settle(tester);
    expect(titlesInOrder(tester, kTitles), <String>[
      'Field Guide To Paper',
      'Press Lease',
      'House Style',
      'Press Run Costs',
      'Subscribers',
      'Bindery Notes',
    ]);
  });

  testWidgets('the direction turns the arrow over and the list with it', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final upright = tester
        .widget<Transform>(find.ancestor(
          of: find.byIcon(LucideIcons.arrowDown),
          matching: find.byType(Transform),
        ).first)
        .transform
        .clone();

    await openMenu(tester);
    await tester.tap(menuRow('Old to new'));
    await settle(tester);

    expect(titlesInOrder(tester, kTitles), kTitles.reversed.toList());
    final turned = tester
        .widget<Transform>(find.ancestor(
          of: find.byIcon(LucideIcons.arrowDown),
          matching: find.byType(Transform),
        ).first)
        .transform;
    expect(turned, isNot(upright));

    await openMenu(tester);
    expect(checked(tester), <String>['Date modified', 'Old to new']);
  });

  test('the sort is one comparison, and the direction only reverses it', () {
    final tabbed = shellEntries(
      libraryEntries,
      DeskTab.recent,
      SortField.name,
      SortOrder.newToOld,
      (entry) => null,
    );
    final back = shellEntries(
      libraryEntries,
      DeskTab.recent,
      SortField.name,
      SortOrder.oldToNew,
      (entry) => null,
    );
    expect(
      back.map((entry) => entry.title).toList(),
      tabbed.reversed.map((entry) => entry.title).toList(),
    );
  });
}
