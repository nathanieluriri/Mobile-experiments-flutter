import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/document_card.dart';
import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/screens/desk/grid_body.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/dissolve/dissolve_scope.dart';

import 'desk_test.dart' show deskStore;
import 'list_body_test.dart' show bodyApp;
import 'support/golden.dart';

List<Object> _jobs(WidgetTester tester) =>
    DissolveScope.of(tester.element(find.byType(GridBody))).jobs;

void main() {
  group('a card leaving the grid', () {
    testWidgets('comes apart, and the grid closes over it only after', (
      tester,
    ) async {
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

      // The second card on the desk, so there is a card beside it and cards
      // under it that would move if the grid closed early.
      final removed = library.visible[1];
      final beside = tester.getRect(find.byType(DocumentCard).at(2));
      library.remove(removed);
      entries.value = library.visible;
      await tester.pump();

      // The card comes apart, the way a row does.
      expect(_jobs(tester), hasLength(1));

      await pumpMs(tester, 60);
      expect(tester.getRect(find.byType(DocumentCard).at(2)), beside);
      await pumpMs(tester, kDissolve.inMilliseconds ~/ 2);
      expect(tester.getRect(find.byType(DocumentCard).at(2)), beside);

      for (var waited = 0;
          waited < 4000 && _jobs(tester).isNotEmpty;
          waited += 60) {
        await pumpMs(tester, 60);
      }
      expect(_jobs(tester), isEmpty);
      expect(tester.getRect(find.byType(DocumentCard).at(2)), beside);

      // And then the grid closes over the space, on the layout spring rather
      // than in one frame.
      await pumpMs(tester, 60);
      expect(tester.hasRunningAnimations, isTrue);
      await pumpMs(tester, 120);
      expect(
        tester.hasRunningAnimations,
        isTrue,
        reason: 'the space closes over many frames, not in one',
      );

      await settle(tester);
      expect(find.byType(DocumentCard), findsNWidgets(5));
    });

    testWidgets('a sort takes nothing apart', (tester) async {
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

      entries.value = library.visible.reversed.toList();
      await tester.pump();
      expect(_jobs(tester), isEmpty);
      await settle(tester);
      expect(find.byType(DocumentCard), findsNWidgets(6));
    });
  });

  group('the bin', () {
    test('holds a removal as soon as the next one is made', () async {
      final library = await deskStore();
      final first = library.visible.first;
      final second = library.visible[1];

      library.remove(first);
      expect(library.isBinned(first), isFalse, reason: 'still undoable');

      library.remove(second);
      expect(library.binned.map((e) => e.path), contains(first.path));
      expect(library.entries.map((e) => e.path), isNot(contains(first.path)));
      expect(library.isBinned(second), isFalse);

      // And the one still on offer can still be put back.
      library.undoRemove();
      expect(library.entries.map((e) => e.path), contains(second.path));
    });

    testWidgets('holds what the desk let the offer run out on', (tester) async {
      final library = await deskStore();
      final removed = library.visible.first;
      await pumpScreen(
        tester,
        App(
          routes: <String, WidgetBuilder>{
            kDeskRoute: (context) => DeskScreen(store: library),
          },
        ),
      );
      await settle(tester);

      await tester.tap(find.byType(OverflowTarget).first);
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await tester.pump();
      expect(
        library.entries.map((e) => e.path),
        isNot(contains(removed.path)),
        reason: 'the menu took it off the desk',
      );
      expect(library.isBinned(removed), isFalse);

      // The pill drains, and what was removed is in the bin.
      for (var waited = 0;
          waited < 6000 && !library.isBinned(removed);
          waited += 120) {
        await pumpMs(tester, 120);
      }
      expect(library.binned.map((e) => e.path), contains(removed.path));
      await settle(tester);
    });

    testWidgets('holds it even when the desk goes away first', (tester) async {
      final library = await deskStore();
      final removed = library.visible.first;
      final showing = ValueNotifier<bool>(true);
      addTearDown(showing.dispose);
      await pumpScreen(
        tester,
        App(
          routes: <String, WidgetBuilder>{
            kDeskRoute: (context) => ValueListenableBuilder<bool>(
              valueListenable: showing,
              builder: (context, desk, _) =>
                  desk ? DeskScreen(store: library) : const SizedBox.expand(),
            ),
          },
        ),
      );
      await settle(tester);

      library.remove(removed);
      await tester.pump();

      // A document is opened, or the desk is put away, before the pill has
      // drained. The offer belongs to the desk itself rather than to the
      // screen showing it, so the removal still ends in the bin.
      showing.value = false;
      await tester.pump();
      expect(library.binned.map((e) => e.path), contains(removed.path));
      await settle(tester);
    });
  });
}
