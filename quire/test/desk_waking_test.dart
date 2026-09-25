import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/screens/desk/document_row.dart';
import 'package:quire/services/document_store.dart';
import 'package:quire/theme/metrics.dart';
import 'package:quire/widgets/quire_spinner.dart';

import 'desk_test.dart' show deskApp;
import 'support/fixtures.dart';
import 'support/golden.dart';

/// A desk the phone never answers about, for the moment the read hangs.
class _SilentDesk extends SavedDesk {
  final Completer<Map<String, Object?>> _never =
      Completer<Map<String, Object?>>();

  @override
  Future<Map<String, Object?>> loadState() => _never.future;
}

void main() {
  group('the desk waking', () {
    testWidgets('shows the mark, and nothing of itself, until it has read', (
      tester,
    ) async {
      final store = LibraryStore(catalogue: SavedDesk());
      await pumpScreen(tester, deskApp(store));
      await tester.pump();

      // Not the shipped documents in the shipped order: nothing at all, and
      // the app's own mark while it finds out.
      expect(find.byType(QuireSpinner), findsOneWidget);
      expect(find.byType(DocumentRow), findsNothing);

      await store.boot(parse: false);
      await tester.pump();
      // Read, but the mark is still up: one that came and went inside two
      // frames would read as a fault.
      expect(find.byType(QuireSpinner), findsOneWidget);

      await pumpMs(tester, kDeskWaking.inMilliseconds);
      await settle(tester);
      expect(find.byType(QuireSpinner), findsNothing);
      expect(find.byType(DocumentRow), findsWidgets);
    });

    testWidgets('gives up waiting on a desk that will not be read', (
      tester,
    ) async {
      final store = LibraryStore(catalogue: _SilentDesk());
      unawaited(store.boot(parse: false));
      await pumpScreen(tester, deskApp(store));
      await tester.pump();
      expect(find.byType(QuireSpinner), findsOneWidget);

      await pumpMs(tester, kDeskWakingLimit.inMilliseconds);
      await settle(tester);
      // A mark that never goes is worse than a desk that is a little wrong.
      expect(find.byType(QuireSpinner), findsNothing);
      expect(find.byType(DocumentRow), findsWidgets);
    });

    testWidgets('a desk with nowhere to read from is up from the first frame', (
      tester,
    ) async {
      final store = LibraryStore();
      await pumpScreen(tester, deskApp(store));
      await tester.pump();
      expect(find.byType(QuireSpinner), findsNothing);
      expect(find.byType(DocumentRow), findsWidgets);
      await settle(tester);
    });

    testWidgets('desk__waking', (tester) async {
      final store = LibraryStore(catalogue: SavedDesk());
      await pumpScreen(tester, deskApp(store));
      await pumpMs(tester, 300);
      await capture(tester, 'desk__waking');
      await store.boot(parse: false);
      await pumpMs(tester, kDeskWaking.inMilliseconds);
      await settle(tester);
    });
  });
}
