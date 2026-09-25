import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/services/document_store.dart';

void main() {
  late LibraryStore desk;
  late LibraryEntry guide;
  late LibraryEntry lease;

  setUp(() {
    desk = LibraryStore();
    guide = desk.entries.first;
    lease = desk.entries[1];
  });

  test('a desk starts with no folders', () {
    expect(desk.folders, isEmpty);
    expect(desk.folderOf(guide), isNull);
  });

  test('moving into a folder makes the folder', () {
    desk.moveTo(guide, 'Press');
    expect(desk.folders, <String>['Press']);
    expect(desk.folderOf(guide), 'Press');
    expect(desk.inFolder('Press'), <LibraryEntry>[guide]);
  });

  test('a folder can be made empty and stay', () {
    desk.makeFolder('Press');
    expect(desk.folders, <String>['Press']);
    expect(desk.countIn('Press'), 0);
  });

  test('two folders cannot share a name, whatever the case', () {
    desk.makeFolder('Press');
    desk.makeFolder('press');
    expect(desk.folders, hasLength(1));
  });

  test('a document is in one folder at a time', () {
    desk.moveTo(guide, 'Press');
    desk.moveTo(guide, 'Bindery');
    expect(desk.folderOf(guide), 'Bindery');
    expect(desk.inFolder('Press'), isEmpty);
    // The first folder is still there, empty.
    expect(desk.folders, <String>['Press', 'Bindery']);
  });

  test('taking it out puts it back on the open desk', () {
    desk.moveTo(guide, 'Press');
    desk.moveTo(guide, null);
    expect(desk.folderOf(guide), isNull);
    expect(desk.folders, <String>['Press']);
  });

  test('removing a folder keeps every document in it', () {
    desk.moveTo(guide, 'Press');
    desk.moveTo(lease, 'Press');
    desk.removeFolder('Press');
    expect(desk.folders, isEmpty);
    expect(desk.folderOf(guide), isNull);
    expect(desk.folderOf(lease), isNull);
    expect(desk.entries, contains(guide));
    expect(desk.entries, contains(lease));
  });

  test('a folder notifies the desk when it changes', () {
    var beats = 0;
    desk.addListener(() => beats++);
    desk.moveTo(guide, 'Press');
    expect(beats, greaterThan(0));
  });

  test('an unnamed folder is not made', () {
    desk.makeFolder('   ');
    expect(desk.folders, isEmpty);
  });

  group('renaming a folder', () {
    test('keeps what is in it', () {
      desk.moveTo(guide, 'Press');
      expect(desk.renameFolder('Press', 'Printing'), 'Printing');
      expect(desk.folders, <String>['Printing']);
      expect(desk.folderOf(guide), 'Printing');
    });

    test('will not take a name another folder has', () {
      desk.makeFolder('Press');
      desk.makeFolder('Bindery');
      expect(desk.renameFolder('Bindery', ' press '), isNull);
      expect(desk.folders, <String>['Press', 'Bindery']);
    });

    test('will not take a blank name', () {
      desk.makeFolder('Press');
      expect(desk.renameFolder('Press', '  '), isNull);
      expect(desk.folders, <String>['Press']);
    });
  });
}
