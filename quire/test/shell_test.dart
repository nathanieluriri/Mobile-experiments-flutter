import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:quire/screens/desk/desk_top_bar.dart';
import 'package:quire/screens/desk/search_pill.dart';
import 'package:quire/screens/desk/shell_model.dart';
import 'package:quire/screens/desk/sort_row.dart';
import 'package:quire/screens/desk/tab_strip.dart';
import 'package:quire/theme/metrics.dart';

import 'desk_test.dart' show deskApp, deskStore;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// The tab pill carrying [label], rather than the type mark of a document that
/// happens to spell the same three letters.
Finder tabNamed(String label) => find.descendant(
      of: find.byType(TabStrip),
      matching: find.text(label),
    );

/// Brings a tab into the strip's own scroll and taps it.
///
/// Five tabs are wider than the phone by design, so the last of them has to be
/// reached the way a reader reaches it.
Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    tabNamed(label),
    60,
    scrollable: find.descendant(
      of: find.byType(TabStrip),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(tabNamed(label));
  await settle(tester);
}

/// Every document title on screen, top to bottom, which is the order the list
/// is actually in rather than the order the model says it is.
List<String> titlesInOrder(WidgetTester tester, List<String> titles) {
  final present =
      titles.where((t) => documentTitled(t).evaluate().isNotEmpty);
  final placed = present
      .map((t) => (title: t, y: tester.getTopLeft(documentTitled(t)).dy))
      .toList()
    ..sort((a, b) => a.y.compareTo(b.y));
  return placed.map((row) => row.title).toList();
}

const kTitles = <String>[
  'Field Guide To Paper',
  'Press Lease',
  'House Style',
  'Press Run Costs',
  'Subscribers',
  'Bindery Notes',
];

void main() {
  testWidgets('the four parts stack, and only the body scrolls', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    // Top bar, tab strip, sort row, body, in that order and at those heights.
    final bar = tester.getRect(find.byType(DeskTopBar));
    expect(bar.top, kSafeTop);
    expect(bar.height, kTopBarHeight);

    final tabs = tester.getRect(find.byType(TabStrip));
    expect(tabs.top, bar.bottom);
    expect(tabs.height, kTabStripHeight);

    final sort = tester.getRect(find.byType(SortRow));
    expect(sort.top, tabs.bottom);
    expect(sort.height, kSortRowHeight);

    // The body starts where the sort row stops. Nothing scrolls under the
    // chrome, so there is no collapse to get wrong and no bar to fade in.
    expect(tester.getTopLeft(documentTitled('Field Guide To Paper')).dy,
        greaterThan(sort.bottom));
  });

  testWidgets('the top bar carries the menu, the pill and the avatar', (
    tester,
  ) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    expect(find.byType(HamburgerGlyph), findsOneWidget);
    expect(find.text(kSearchPlaceholder), findsOneWidget);
    expect(find.text('N'), findsOneWidget);

    final glyph = tester.getRect(find.byType(HamburgerGlyph));
    expect(glyph.left, kTopBarPaddingX);
    expect(glyph.size, const Size(kBurgerTarget, kBurgerTarget));

    final pill = tester.getRect(find.byType(SearchPill));
    expect(pill.height, kSearchPillHeight);
    expect(pill.right, lessThan(kScreenWidth - kTopBarPaddingX - kAvatarSize));
  });

  testWidgets('a tab counts what it holds and shows only that', (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    for (final tab in DeskTab.values) {
      expect(tabNamed(tab.label), findsOneWidget, reason: tab.label);
    }
    // RECENT holds everything, and the four format tabs partition it.
    expect(
      find.descendant(of: find.byType(TabStrip), matching: find.text('6')),
      findsOneWidget,
    );

    // PDF is already under the thumb, so the strip is where a reader first
    // meets it and the golden shows the whole row.
    await tester.tap(tabNamed('PDF'));
    await settle(tester);
    expect(titlesInOrder(tester, kTitles), <String>[
      'Field Guide To Paper',
      'Press Lease',
    ]);
    // The colophon under the list counts the list. Two rows over a line that
    // says six would be the desk disagreeing with itself in one glance.
    expect(find.textContaining('2 DOCUMENTS'), findsOneWidget);
    await capture(tester, 'desk__tab_pdf');

    await tapTab(tester, 'NOTES');
    expect(titlesInOrder(tester, kTitles), <String>['Bindery Notes']);

    await tapTab(tester, 'SHEETS');
    expect(titlesInOrder(tester, kTitles), <String>[
      'Press Run Costs',
      'Subscribers',
    ]);
  });

  testWidgets('the toggles change the layout and nothing else', (tester) async {
    final store = await deskStore();
    await pumpScreen(tester, deskApp(store));
    await settle(tester);

    final before = titlesInOrder(tester, kTitles);
    // The two views under the same chrome, which is the only place either of
    // them is ever seen.
    await capture(tester, 'desk__list');

    await tester.tap(find.byIcon(LucideIcons.layoutGrid));
    await settle(tester);

    // The same six documents, two to a row, in the same order. A view is a
    // layout and never a filter.
    expect(titlesInOrder(tester, kTitles), before);
    await capture(tester, 'desk__grid');
    final first = tester.getTopLeft(documentTitled(before.first));
    final second = tester.getTopLeft(documentTitled(before[1]));
    expect(second.dx, greaterThan(first.dx));
    // Side by side. A title that wraps to two lines sets its first line a
    // little higher inside the same card header, so the pair share a row
    // rather than sharing a baseline.
    expect((second.dy - first.dy).abs(), lessThan(kGridCardHeaderHeight));

    await tester.tap(find.byIcon(LucideIcons.list));
    await settle(tester);
    expect(
      tester.getTopLeft(documentTitled(before[1])).dy,
      greaterThan(tester.getTopLeft(documentTitled(before.first)).dy),
    );
  });
}
