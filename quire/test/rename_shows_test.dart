import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/widgets/marked_text.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

Future<LibraryStore> _desk() async {
  final store = LibraryStore();
  for (final entry in libraryEntries) {
    store.storeFor(entry).loadFrom(await documentBytes(entry.fileName));
  }
  return store;
}

/// A row's title, which the desk sets as marked text so a search can be lit
/// inside it, and so is not a plain [Text] for [find.text] to find.
Finder _titled(String title) => find.byWidgetPredicate(
  (widget) => widget is MarkedText && widget.text == title,
);

Widget _app(LibraryStore store) => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => DeskScreen(store: store),
  },
);

void main() {
  group('a renamed document', () {
    testWidgets('says its new name on the list, where it was renamed', (
      tester,
    ) async {
      final store = await _desk();
      await pumpScreen(tester, _app(store));
      await settle(tester);

      final guide = store.entries.firstWhere(
        (e) => e.fileName == 'field-guide-to-paper.pdf',
      );
      expect(_titled(guide.title), findsOneWidget);

      store.rename(guide, 'Paper, Notes On');
      await settle(tester);

      // Without switching to the grid and back, which is what used to be
      // needed: the list held its own copies of the entries and a rename
      // leaves the path alone, so nothing told it to take the new ones.
      expect(_titled('Paper, Notes On'), findsOneWidget);
      expect(_titled('Field Guide To Paper'), findsNothing);
    });

    testWidgets('keeps everything else about it', (tester) async {
      final store = await _desk();
      await pumpScreen(tester, _app(store));
      await settle(tester);

      final lease = store.entries.firstWhere(
        (e) => e.fileName == 'press-lease.pdf',
      );
      final was = store.entries.length;
      store
        ..toggleStar(lease)
        ..rename(lease, 'The Lease');
      await settle(tester);

      expect(_titled('The Lease'), findsOneWidget);
      expect(store.entries.length, was);
      final now = store.entries.firstWhere((e) => e.path == lease.path);
      expect(store.isStarred(now), isTrue);
      expect(now.format, lease.format);
      expect(now.bytes, lease.bytes);
    });

    testWidgets('the rest of the list is left alone', (tester) async {
      final store = await _desk();
      await pumpScreen(tester, _app(store));
      await settle(tester);

      final guide = store.entries.firstWhere(
        (e) => e.fileName == 'field-guide-to-paper.pdf',
      );
      store.rename(guide, 'Paper, Notes On');
      await settle(tester);

      for (final other in store.entries) {
        if (other.path == guide.path) continue;
        expect(_titled(other.title), findsOneWidget, reason: other.title);
      }
    });
  });
}
