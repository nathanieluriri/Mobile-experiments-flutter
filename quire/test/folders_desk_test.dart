import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/folder_body.dart';
import 'package:quire/services/document_store.dart';

import 'support/golden.dart';

Widget _app(LibraryStore store) => App(
  routes: <String, WidgetBuilder>{
    kDeskRoute: (context) => DeskScreen(store: store),
  },
);

Future<void> _openFolders(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('menu', caseSensitive: false)).first);
  await settle(tester);
  await tester.tap(find.text('Folders').last);
  await settle(tester);
}

void main() {
  group('the Folders list', () {
    testWidgets('offers New folder even before there are any', (tester) async {
      final store = LibraryStore();
      await pumpScreen(tester, _app(store));
      await settle(tester);
      await _openFolders(tester);

      expect(find.byType(NewFolderRow), findsOneWidget);
      await tester.tap(find.byType(NewFolderRow));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).last, 'Press');
      await tester.tap(find.text('Make the folder'));
      await settle(tester);

      expect(store.folders, <String>['Press']);
      expect(find.text('Press'), findsWidgets);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      await capture(tester, 'desk__folders');
    });

    testWidgets('back inside a folder leaves the folder, not the app', (
      tester,
    ) async {
      final store = LibraryStore();
      store.moveTo(store.entries.first, 'Press');
      await pumpScreen(tester, _app(store));
      await settle(tester);
      await _openFolders(tester);
      await tester.tap(find.text('Press').last);
      await settle(tester);
      expect(find.byType(FolderCrumb), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await settle(tester);
      expect(handled, isTrue);
      expect(find.byType(FolderCrumb), findsNothing);
      expect(find.byType(DeskScreen), findsOneWidget);
    });

    testWidgets('the dots in the crumb rename the folder you are in', (
      tester,
    ) async {
      final store = LibraryStore();
      store.moveTo(store.entries.first, 'Press');
      await pumpScreen(tester, _app(store));
      await settle(tester);
      await _openFolders(tester);
      await tester.tap(find.text('Press').last);
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('What can be done with Press'));
      await settle(tester);
      await tester.tap(find.text('Rename folder'));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).last, 'Printing');
      await tester.tap(find.text('Save the name'));
      await settle(tester);

      expect(store.folders, <String>['Printing']);
      final crumb = tester.widget<FolderCrumb>(find.byType(FolderCrumb));
      expect(crumb.folder, 'Printing');
      expect(crumb.held, 1);
    });
  });
}
