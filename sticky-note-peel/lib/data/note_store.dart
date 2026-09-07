import 'package:flutter/foundation.dart';

import '../theme/metrics.dart';
import 'note.dart';
import 'note_file.dart';
import 'notes.dart';

/// The notes, what is being looked for in them, and what is written to disk.
///
/// Everything the screen draws comes from [visible]; [notes] is the whole list
/// and is what gets saved.
class NoteStore extends ChangeNotifier {
  NoteStore({List<Note>? notes, this.file})
      : _notes = List<Note>.of(notes ?? kNotes);

  final List<Note> _notes;

  /// Where the list is saved, or null to keep it in memory only.
  final NoteFile? file;

  String? _tagFilter;
  String _query = '';

  List<Note> get notes => List<Note>.unmodifiable(_notes);

  /// The tag the drawer is filtering by, or null for everything.
  String? get tagFilter => _tagFilter;

  /// What has been typed into the search field.
  String get query => _query;

  bool get isSearching => _query.isNotEmpty;

  /// What the list shows: the notes that carry the chosen tag and contain the
  /// query, in the order they were added.
  List<Note> get visible => _notes.where(matches).toList();

  bool matches(Note note) {
    if (_tagFilter != null && !note.tags.contains(_tagFilter)) {
      return false;
    }
    if (_query.isEmpty) {
      return true;
    }
    return note.searchText.contains(_query.trim().toLowerCase());
  }

  /// Every tag in use with how many notes carry it, in the order the tags first
  /// appear in the list, so the drawer does not reshuffle as notes are added.
  Map<String, int> get tagCounts {
    final counts = <String, int>{};
    for (final note in _notes) {
      for (final tag in note.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The heading over the list: the chosen tag, or the default title.
  String get title => _tagFilter ?? kNotesScreenTitle;

  void setTagFilter(String? tag) {
    if (_tagFilter == tag) {
      return;
    }
    _tagFilter = tag;
    notifyListeners();
  }

  void setQuery(String query) {
    if (_query == query) {
      return;
    }
    _query = query;
    notifyListeners();
  }

  /// Puts a new note at the top of the list, where it can be seen.
  void add(Note note) {
    _notes.insert(0, note);
    _persist();
    notifyListeners();
  }

  /// Puts an edited note back where it was.
  void update(Note note) {
    final index = _notes.indexWhere((existing) => existing.id == note.id);
    if (index < 0) {
      return;
    }
    _notes[index] = note;
    if (_tagFilter != null && !tagCounts.containsKey(_tagFilter)) {
      _tagFilter = null;
    }
    _persist();
    notifyListeners();
  }

  void remove(String id) {
    final index = _notes.indexWhere((note) => note.id == id);
    if (index < 0) {
      return;
    }
    _notes.removeAt(index);
    // A tag can disappear with the last note carrying it, and a filter on a tag
    // nothing carries would show an empty list with no way back.
    if (_tagFilter != null && !tagCounts.containsKey(_tagFilter)) {
      _tagFilter = null;
    }
    _persist();
    notifyListeners();
  }

  /// An id no note in the list is using.
  String nextId(String seed) {
    final base = seed
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = base.isEmpty ? 'note' : base;
    var candidate = stem;
    var suffix = 2;
    while (_notes.any((note) => note.id == candidate)) {
      candidate = '$stem-$suffix';
      suffix++;
    }
    return candidate;
  }

  /// Replaces the list with what was saved last time, if anything was.
  Future<void> load() async {
    final saved = await file?.read();
    if (saved == null || saved.isEmpty) {
      return;
    }
    _notes
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  void _persist() {
    file?.write(List<Note>.of(_notes));
  }
}
