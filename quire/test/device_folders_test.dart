import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/app.dart';
import 'package:quire/data/library.dart';
import 'package:quire/screens/desk/desk_screen.dart';
import 'package:quire/screens/desk/folder_body.dart';
import 'package:quire/screens/desk/shell_model.dart';
import 'package:quire/services/device_storage.dart';
import 'package:quire/services/document_store.dart';

import 'support/fixtures.dart';
import 'support/golden.dart';

/// A phone with one handed over folder, Downloads, holding a PDF, a photo, a
/// subfolder with a note in it, and whatever the test adds.
class _FakePhone {
  final calls = <MethodCall>[];
  final folders = <String, List<Map<String, Object?>>>{
    'root': [
      {'document': 'd/lease.pdf', 'uri': 'content://t/lease.pdf', 'name': 'lease.pdf', 'folder': false, 'size': 1200, 'modified': 5},
      {'document': 'd/photo.jpg', 'uri': 'content://t/photo.jpg', 'name': 'photo.jpg', 'folder': false, 'size': 99, 'modified': 5},
      {'document': 'd/notes', 'uri': 'content://t/notes', 'name': 'notes', 'folder': true, 'size': 0, 'modified': 5},
      // A row the phone got wrong is not a row.
      {'document': 7, 'name': null},
    ],
    'd/notes': [
      {'document': 'd/notes/todo.md', 'uri': 'content://t/notes/todo.md', 'name': 'todo.md', 'folder': false, 'size': 20, 'modified': 5},
    ],
  };
  var gone = false;
  final bytes = <String, Uint8List>{};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'adopt':
        return <String, Object?>{'tree': 'content://tree/downloads', 'name': 'Download'};
      case 'granted':
        return <Object?>[];
      case 'list':
        if (gone) throw PlatformException(code: 'gone');
        return folders[args['document'] ?? 'root'] ?? <Object?>[];
      case 'makeFolder':
        final name = args['name']! as String;
        final made = {'document': 'd/$name', 'uri': 'content://t/$name', 'name': name, 'folder': true, 'size': 0, 'modified': 9};
        folders.putIfAbsent(args['document'] as String? ?? 'root', () => []).add(made);
        return made;
      case 'read':
        final uri = args['uri']! as String;
        final held = bytes[uri];
        if (held == null) throw PlatformException(code: 'gone');
        return held;
      case 'release':
        return null;
    }
    return null;
  }

  int count(String method) => calls.where((c) => c.method == method).length;
}

_FakePhone _install() {
  final phone = _FakePhone();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kDeviceStorageChannel, phone.handle);
  addTearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kDeviceStorageChannel, null));
  return phone;
}

class _Remembering extends SavedDesk {
  _Remembering();
  Map<String, Object?>? saved;

  @override
  Future<void> saveState(Map<String, Object?> state) async => saved = state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the phone, through the platform', () {
    test('a folder lists its folders first and drops what it got wrong', () async {
      _install();
      final items = await const DeviceStorage().list('content://tree/downloads');
      expect(items.map((i) => i.name), ['notes', 'lease.pdf', 'photo.jpg']);
      expect(items.first.folder, isTrue);
      expect(items[1].format, DocFormat.pdf);
      expect(items[2].format, isNull);
    });

    test('the documents under a folder are walked, and only what quire reads', () async {
      _install();
      final found = await const DeviceStorage().documents('content://tree/downloads');
      expect(found.map((i) => i.name), ['todo.md', 'lease.pdf']);
      final shallow = await const DeviceStorage().documents('content://tree/downloads', depth: 0);
      expect(shallow.map((i) => i.name), ['lease.pdf']);
      final few = await const DeviceStorage().documents('content://tree/downloads', limit: 1);
      expect(few, hasLength(1));
    });

    test('a folder the phone will not read any more says so', () async {
      _install().gone = true;
      expect(
        () => const DeviceStorage().list('content://tree/downloads'),
        throwsA(isA<DeviceFolderGone>()),
      );
    });

    test('with no phone underneath, nothing is adopted', () async {
      expect(await const DeviceStorage().adopt(), isNull);
      expect(await const DeviceStorage().available, isFalse);
    });

    test('a document on the phone is an entry read in place', () {
      final entry = LibraryEntry.onDevice(
        uri: 'content://t/Press-Run%20Costs.xlsx',
        name: 'press-run costs.xlsx',
        format: DocFormat.xlsx,
        bytes: 10,
      );
      expect(entry.fileName, 'press-run costs.xlsx');
      expect(entry.onDevice, isTrue);
      expect(entry.renamed('Costs').fileName, 'press-run costs.xlsx');
    });
  });

  group('the desk and the phone', () {
    test('an adopted folder is kept, read, and remembered', () async {
      final phone = _install();
      final catalogue = _Remembering();
      final store = LibraryStore(entries: const [], catalogue: catalogue);
      await store.boot(parse: false);
      final folder = await store.adoptFolder();
      expect(folder?.name, 'Download');
      expect(store.adopted, [folder]);
      expect(store.onDevice.map((e) => e.fileName), ['todo.md', 'lease.pdf']);
      expect(store.entries, isEmpty, reason: 'nothing on the phone is copied in');
      store.storeFor(store.onDevice.last).markOpened();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final saved = catalogue.saved!;
      expect(saved['adopted'], [folder!.toJson()]);

      // The next run brings the folder and the reading back.
      final again = LibraryStore(entries: const [], catalogue: SavedDesk(saved));
      await again.boot(parse: false);
      await again.scanDevice();
      expect(again.adopted.single.tree, 'content://tree/downloads');
      final lease = again.onDevice.firstWhere((e) => e.fileName == 'lease.pdf');
      expect(again.storeFor(lease).opened, isTrue);
      expect(phone.count('adopt'), 1);
    });

    test('a folder that has gone is kept and marked, not dropped', () async {
      final phone = _install();
      final store = LibraryStore(entries: const [], catalogue: SavedDesk());
      await store.boot(parse: false);
      final folder = (await store.adoptFolder())!;
      phone.gone = true;
      await store.scanDevice();
      expect(store.isMissing(folder), isTrue);
      expect(store.adopted, [folder]);
      expect(store.onDevice, isEmpty);
      await store.forgetFolder(folder);
      expect(store.adopted, isEmpty);
      expect(phone.count('release'), 1);
    });

    test('a document on the phone is read when it is opened, and not before',
        () async {
      final phone = _install();
      phone.bytes['content://t/notes/todo.md'] =
          Uint8List.fromList('# To do\n\nRead the lease.'.codeUnits);
      final store = LibraryStore(entries: const [], catalogue: SavedDesk());
      await store.boot();
      await store.adoptFolder();
      expect(phone.count('read'), 0);
      final todo = store.onDevice.firstWhere((e) => e.fileName == 'todo.md');
      await store.readNow(todo);
      expect(phone.count('read'), 1);
      expect(store.storeFor(todo).state, ParseState.ready);
    });

    test('a document that cannot be read from the phone is the damaged state',
        () async {
      _install();
      final store = LibraryStore(entries: const [], catalogue: SavedDesk());
      await store.boot(parse: false);
      await store.adoptFolder();
      final lease = store.onDevice.firstWhere((e) => e.fileName == 'lease.pdf');
      await store.readNow(lease);
      expect(store.storeFor(lease).state, ParseState.failed);
    });
  });

  group('the tabs', () {
    test('ALL is everything and RECENT is only what was opened, newest first',
        () async {
      final store = LibraryStore();
      final entries = store.entries;
      final first = store.storeFor(entries[2])..markOpened();
      final second = store.storeFor(entries[4]);
      expect(DeskTab.all.holds(entries[0]), isTrue);
      expect(DeskTab.recent.holds(entries[2], first), isTrue);
      expect(DeskTab.recent.holds(entries[4], second), isFalse);
      expect(DeskTab.recent.holds(entries[0]), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      second.markOpened();
      final recent = shellEntries(
        entries,
        DeskTab.recent,
        SortField.name,
        SortOrder.newToOld,
        store.peek,
      );
      expect(recent, [entries[4], entries[2]]);
    });

    test('ALL comes first in the strip', () {
      expect(DeskTab.values.first, DeskTab.all);
      expect(DeskTab.values.map((t) => t.label), [
        'ALL', 'RECENT', 'PDF', 'DOCS', 'SHEETS', 'NOTES',
      ]);
    });
  });

  group('the desk with a folder on the phone', () {
    Widget app(LibraryStore store) => App(
          routes: <String, WidgetBuilder>{
            kDeskRoute: (context) => DeskScreen(store: store),
          },
        );

    Future<void> openFolders(WidgetTester tester) async {
      await tester.tap(
        find.bySemanticsLabel(RegExp('menu', caseSensitive: false)).first,
      );
      await settle(tester);
      await tester.tap(find.text('Folders').last);
      await settle(tester);
    }

    Future<(LibraryStore, _FakePhone)> adopted() async {
      final phone = _install();
      final store = LibraryStore(catalogue: SavedDesk());
      await store.boot(parse: false);
      await store.adoptFolder();
      return (store, phone);
    }

    testWidgets('ALL counts the phone documents in with quire\'s own', (
      tester,
    ) async {
      final (store, _) = await adopted();
      await pumpScreen(tester, app(store));
      await settle(tester);
      expect(store.onDevice, hasLength(2));
      final count = '${libraryEntries.length + 2}';
      expect(find.text(count), findsWidgets);
      expect(find.textContaining('on the phone'), findsWidgets);
      // A search finds a document on the phone by its name.
      store.query = 'todo';
      await settle(tester);
      expect(
        find.textContaining('on the phone', findRichText: true),
        findsOneWidget,
      );
      expect(documentTitled('Todo'), findsWidgets);
    });

    testWidgets('the Folders list holds the phone folder, and it opens', (
      tester,
    ) async {
      final (store, phone) = await adopted();
      await pumpScreen(tester, app(store));
      await settle(tester);
      await openFolders(tester);
      expect(find.byType(AdoptFolderRow), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('On the phone'), findsOneWidget);

      await tester.tap(find.text('Download'));
      await settle(tester);
      expect(find.byType(FolderCrumb), findsOneWidget);
      expect(find.widgetWithText(DeviceFolderRow, 'notes'), findsOneWidget);
      expect(find.textContaining('on the phone'), findsOneWidget);
      expect(find.textContaining('photo'), findsNothing);

      // A folder made here is made on the phone.
      await tester.tap(find.byType(NewFolderRow));
      await settle(tester);
      await tester.enterText(find.byType(EditableText).last, 'Leases');
      await tester.tap(find.text('Make the folder'));
      await settle(tester);
      expect(phone.count('makeFolder'), 1);
      expect(find.widgetWithText(DeviceFolderRow, 'Leases'), findsOneWidget);

      // Into the subfolder, and back out one level at a time.
      await tester.tap(find.text('notes'));
      await settle(tester);
      expect(documentTitled('Todo'), findsWidgets);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.widgetWithText(DeviceFolderRow, 'notes'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(FolderCrumb), findsNothing);
      expect(find.byType(AdoptFolderRow), findsOneWidget);
    });

    testWidgets('a folder that has gone says so where it stood', (
      tester,
    ) async {
      final (store, phone) = await adopted();
      phone.gone = true;
      await store.scanDevice();
      await pumpScreen(tester, app(store));
      await settle(tester);
      await openFolders(tester);
      expect(find.text('Not on the phone any more'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await settle(tester);
      expect(find.text('This folder is not on the phone any more'),
          findsOneWidget);
      await tester.tap(find.text('Stop showing it'));
      await settle(tester);
      expect(store.adopted, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
