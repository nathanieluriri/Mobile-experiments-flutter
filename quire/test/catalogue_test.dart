import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/services/library_catalogue.dart';

/// The catalogue is written at the moment the app is going away, which is the
/// moment the system is most likely to stop it mid sentence. These are the
/// tests for what the desk still has the next morning.
void main() {
  const storage = MethodChannel('plugins.flutter.io/path_provider');

  late Directory home;
  late Directory imports;
  late LibraryCatalogue catalogue;

  setUp(() {
    home = Directory.systemTemp.createTempSync('quire_catalogue');
    imports = Directory('${home.path}${Platform.pathSeparator}imports');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return home.path;
          }
          return null;
        });
    catalogue = LibraryCatalogue();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, null);
    try {
      if (home.existsSync()) home.deleteSync(recursive: true);
    } on FileSystemException {
      // A folder left in the system temp is not worth failing a test over.
    }
  });

  File fileIn(String name) =>
      File('${imports.path}${Platform.pathSeparator}$name');

  /// A file stopped part way through being written: the bytes that did land
  /// are not a JSON object, which is exactly what a kill mid write leaves.
  void tear(String name) => fileIn(name).writeAsStringSync('{"version": 1, "s');

  /// A document the reader brought in, described the way the desk describes
  /// one. The file has to exist or [LibraryCatalogue.load] skips the entry.
  LibraryEntry entryFor(String name) {
    if (!imports.existsSync()) imports.createSync(recursive: true);
    final file = fileIn(name)..writeAsStringSync('page one');
    return LibraryEntry(
      path: file.path,
      title: LibraryEntry.titleFor(name),
      format: DocFormat.md,
      bytes: 8,
      source: DocSource.file,
    );
  }

  group('what a write leaves on disk', () {
    test('a finished save leaves no half written file beside it', () async {
      await catalogue.saveState(<String, Object?>{'position': 3});

      final left = imports
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.endsWith('.tmp'))
          .toList();
      expect(left, isEmpty, reason: 'a draft must not outlive its write');
      expect(fileIn('state.json').existsSync(), isTrue);
    });

    test('the second save keeps the first one beside it', () async {
      await catalogue.saveState(<String, Object?>{'position': 1});
      await catalogue.saveState(<String, Object?>{'position': 2});

      expect(fileIn('state.json.bak').existsSync(), isTrue);
    });
  });

  group('what the desk still has after a torn write', () {
    test('a torn state file falls back to the one before it', () async {
      await catalogue.saveState(<String, Object?>{'position': 1});
      await catalogue.saveState(<String, Object?>{'position': 2});
      tear('state.json');

      expect((await catalogue.loadState())['position'], 1);
    });

    test('a state file lost between the two moves falls back', () async {
      await catalogue.saveState(<String, Object?>{'position': 1});
      await catalogue.saveState(<String, Object?>{'position': 2});
      // The instant after the live file is taken away and before the draft
      // has been moved into its place.
      fileIn('state.json').deleteSync();

      expect((await catalogue.loadState())['position'], 1);
    });

    test('a torn index still lists the documents it had', () async {
      await catalogue.save(<LibraryEntry>[entryFor('first.md')]);
      await catalogue.save(<LibraryEntry>[
        entryFor('first.md'),
        entryFor('second.md'),
      ]);
      tear('library.json');

      final entries = await catalogue.load();
      expect(entries.map((e) => e.title), <String>['First']);
    });

    test('bytes that are not even text are survived', () async {
      await catalogue.saveState(<String, Object?>{'position': 7});
      await catalogue.saveState(<String, Object?>{'position': 8});
      fileIn('state.json').writeAsBytesSync(<int>[0xC3, 0x28, 0xA0, 0xFF]);

      expect((await catalogue.loadState())['position'], 7);
    });

    test('a torn file with nothing beside it is a fresh start', () async {
      await catalogue.saveState(<String, Object?>{'position': 1});
      tear('state.json');
      final backup = fileIn('state.json.bak');
      if (backup.existsSync()) backup.deleteSync();

      expect(await catalogue.loadState(), isEmpty);
    });

    test('nothing written yet is a fresh start, not a failure', () async {
      expect(await catalogue.loadState(), isEmpty);
      expect(await catalogue.load(), isEmpty);
    });
  });
}
