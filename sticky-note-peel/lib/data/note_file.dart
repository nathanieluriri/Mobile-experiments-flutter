import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'note.dart';

/// Where the notes live between launches.
///
/// Every call fails quietly. Losing the file costs the notes written since the
/// last launch; throwing out of it would cost the whole screen, so it never
/// throws.
class NoteFile {
  const NoteFile({this.name = 'notes.json'});

  final String name;

  Future<File> _handle() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  /// The saved notes, or null when nothing has been saved yet or the file
  /// cannot be read.
  Future<List<Note>?> read() async {
    try {
      final file = await _handle();
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return null;
      }
      return decoded.map(Note.fromJson).nonNulls.toList();
    } on Object {
      return null;
    }
  }

  Future<void> write(List<Note> notes) async {
    try {
      final file = await _handle();
      await file.writeAsString(
        jsonEncode([for (final note in notes) note.toJson()]),
        flush: true,
      );
    } on Object {
      return;
    }
  }
}
