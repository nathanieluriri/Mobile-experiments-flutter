import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/reader/reader_route.dart';
import 'package:quire/services/document_store.dart';

import 'support/golden.dart';

void main() {
  testWidgets('the app opens on the desk, with its documents read', (
    tester,
  ) async {
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await pumpScreen(tester, const App());
    await settle(tester);

    // The desk lays itself out from the manifest, then the six files are read
    // and their real counts land on the rows already on the ground.
    expect(find.byType(DeskScreen), findsOneWidget);
    expect(
      find.textContaining(RegExp('6 pages', caseSensitive: false)),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp('1,010 words', caseSensitive: false)),
      findsOneWidget,
    );
  });

  testWidgets('a card grows into the reader it was tapped from', (
    tester,
  ) async {
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    late DocumentStore opened;
    await pumpScreen(
      tester,
      App(
        routes: <String, WidgetBuilder>{
          kReaderRoute: (context) {
            final handoff =
                ModalRoute.of(context)!.settings.arguments as ReaderHandoff;
            opened = handoff.store;
            return const SizedBox.expand();
          },
        },
      ),
    );
    await settle(tester);
    await tester.tapAt(const Offset(201, 300));
    await settle(tester);

    // The document the reader was handed is the one whose card was tapped.
    expect(opened.entry.fileName, 'press-lease.pdf');
    expect(opened.opens, 1);
    final route = ModalRoute.of(tester.element(find.byType(SizedBox).last));
    expect(route, isA<ReaderRoute<void>>());
  });
}
