import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticky_note_peel/data/note.dart';
import 'package:sticky_note_peel/data/note_store.dart';
import 'package:sticky_note_peel/data/notes.dart';

Note note(
  String id, {
  List<String> tags = const [],
  String? body,
  List<String>? checklist,
}) {
  return Note(
    id: id,
    color: const Color(0xFFFFD54A),
    title: id,
    body: body,
    checklist: checklist,
    tags: tags,
  );
}

void main() {
  group('what the list shows', () {
    test('everything, until something narrows it', () {
      final store = NoteStore();
      expect(store.visible, hasLength(kNotes.length));
      expect(store.title, 'All notes');
    });

    test('only the notes carrying the chosen tag', () {
      final store = NoteStore(notes: [
        note('a', tags: ['Work']),
        note('b', tags: ['Home']),
        note('c', tags: ['Work', 'Home']),
      ]);
      store.setTagFilter('Work');
      expect(store.visible.map((n) => n.id), ['a', 'c']);
      expect(store.title, 'Work');

      store.setTagFilter(null);
      expect(store.visible, hasLength(3));
      expect(store.title, 'All notes');
    });

    test('only the notes containing the query, wherever it sits', () {
      final store = NoteStore(notes: [
        note('title', body: 'nothing here'),
        note('other', body: 'a Sweater and a coat'),
        note('third', checklist: ['buy a sweater']),
        note('fourth', tags: ['Sweater weather']),
      ]);
      store.setQuery('sweater');
      expect(store.visible.map((n) => n.id), ['other', 'third', 'fourth']);
      expect(store.isSearching, isTrue);

      store.setQuery('');
      expect(store.visible, hasLength(4));
      expect(store.isSearching, isFalse);
    });

    test('the tag and the query together', () {
      final store = NoteStore(notes: [
        note('a', tags: ['Work'], body: 'sweater'),
        note('b', tags: ['Home'], body: 'sweater'),
        note('c', tags: ['Work'], body: 'coat'),
      ]);
      store.setTagFilter('Work');
      store.setQuery('sweater');
      expect(store.visible.map((n) => n.id), ['a']);
    });
  });

  group('the drawer rows', () {
    test('count the notes carrying each tag, in the order they appear', () {
      final store = NoteStore(notes: [
        note('a', tags: ['Work']),
        note('b', tags: ['Home', 'Work']),
        note('c'),
      ]);
      expect(store.tagCounts, {'Work': 2, 'Home': 1});
      expect(store.tagCounts.keys.toList(), ['Work', 'Home']);
    });

    test('a tag disappears with the last note carrying it', () {
      final store = NoteStore(notes: [note('a', tags: ['Work'])]);
      store.setTagFilter('Work');
      store.remove('a');
      expect(store.tagCounts, isEmpty);
      expect(
        store.tagFilter,
        isNull,
        reason: 'a filter on a tag nothing carries would strand the list',
      );
    });
  });

  group('adding and removing', () {
    test('a new note goes to the top and is announced', () {
      final store = NoteStore(notes: [note('a')]);
      var announced = 0;
      store.addListener(() => announced++);

      store.add(note('b'));
      expect(store.notes.map((n) => n.id), ['b', 'a']);
      expect(announced, 1);
    });

    test('removing an id that is not there changes nothing', () {
      final store = NoteStore(notes: [note('a')]);
      var announced = 0;
      store.addListener(() => announced++);

      store.remove('missing');
      expect(store.notes, hasLength(1));
      expect(announced, 0);
    });

    test('a new id never collides with one already in use', () {
      final store = NoteStore(notes: [note('grocery-shopping')]);
      expect(store.nextId('Grocery Shopping'), 'grocery-shopping-2');
      expect(store.nextId('  '), 'note');
      expect(store.nextId('Weekend / plans!'), 'weekend-plans');
    });
  });

  group('saving and reading back', () {
    test('a note survives the round trip', () {
      for (final original in kNotes) {
        final restored = Note.fromJson(
          jsonDecode(jsonEncode(original.toJson())),
        );
        expect(restored, isNotNull);
        expect(restored!.id, original.id);
        expect(restored.color, original.color);
        expect(restored.title, original.title);
        expect(restored.body, original.body);
        expect(restored.checklist, original.checklist);
        expect(restored.meta, original.meta);
        expect(restored.tags, original.tags);
        expect(restored.date, original.date);
      }
    });

    test('an entry missing what a note needs is dropped, not fatal', () {
      expect(Note.fromJson(null), isNull);
      expect(Note.fromJson('a note'), isNull);
      expect(Note.fromJson({'id': 'a'}), isNull);
      expect(Note.fromJson({'id': 'a', 'color': 'red', 'title': 't'}), isNull);
      expect(
        Note.fromJson({'id': 'a', 'color': 0xFFFFD54A, 'title': 't'}),
        isNotNull,
      );
    });

    test('reading nothing back leaves the shipped notes in place', () async {
      final store = NoteStore();
      await store.load();
      expect(store.notes, hasLength(kNotes.length));
    });
  });
}
