import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/document_card.dart';
import 'package:quire/screens/desk/grid_body.dart';
import 'package:quire/screens/desk/thumbnail.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/marked_text.dart';

import 'desk_test.dart' show deskStore;
import 'list_body_test.dart' show bodyApp;
import 'support/golden.dart';

/// Two columns of [kGridPadding] padded cards with [kGridGap] between them, on
/// the phone this app is judged on.
const double kExpectedCardWidth =
    (kScreenWidth - kGridPadding * 2 - kGridGap) / kGridColumns;

void main() {
  testWidgets('the grid lays out two columns of cards, each a real page',
      (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => GridBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    expect(find.byType(DocumentCard), findsNWidgets(6));
    expect(find.byType(Thumbnail), findsNWidgets(6));

    final first = tester.getRect(find.byType(DocumentCard).first);
    final second = tester.getRect(find.byType(DocumentCard).at(1));
    expect(first.width, closeTo(kExpectedCardWidth, 0.01));
    expect(second.left - first.right, closeTo(kGridGap, 0.01));
    expect(second.top, first.top);

    // A card is its header plus a page a little taller than it is wide, and
    // the page is the reason the grid costs that height.
    expect(
      first.height,
      closeTo(
        kGridCardHeaderHeight + kExpectedCardWidth / kThumbnailAspect,
        0.5,
      ),
    );
    final page = tester.getRect(find.byType(Thumbnail).first);
    expect(page.width / page.height, closeTo(kThumbnailAspect, 0.01));

    // The third card starts a second run, one gap below the first.
    final third = tester.getRect(find.byType(DocumentCard).at(2));
    expect(third.left, first.left);
    expect(third.top - first.bottom, closeTo(kGridGap, 0.01));
  });

  testWidgets('every card holds its own document, whatever the format',
      (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => GridBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    // Six documents, five formats, six different pages. Two cards showing the
    // same picture would mean one of them is a placeholder.
    final pages = <Object>{
      for (final entry in library.entries)
        thumbnailOf(library.storeFor(entry)).picture,
    };
    expect(pages, hasLength(library.entries.length));
    for (final entry in library.entries) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is MarkedText && widget.text == entry.title,
        ),
        findsOneWidget,
        reason: entry.title,
      );
    }
  });

  testWidgets('a filter leaves the cards that match', (tester) async {
    final library = await deskStore();
    final entries = ValueNotifier<List<LibraryEntry>>(library.visible);
    addTearDown(entries.dispose);
    await pumpScreen(
      tester,
      bodyApp(
        entries,
        (shown) => GridBody(library: library, entries: shown),
      ),
    );
    await settle(tester);

    entries.value = <LibraryEntry>[
      for (final entry in library.visible)
        if (entry.format == DocFormat.pdf) entry,
    ];
    await settle(tester);
    expect(find.byType(DocumentCard), findsNWidgets(2));
    final first = tester.getRect(find.byType(DocumentCard).first);
    expect(first.width, closeTo(kExpectedCardWidth, 0.01));
  });
}
