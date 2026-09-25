import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../data/library.dart';

/// The documents the reader has brought onto the desk, where they live, and
/// everything the desk remembers about every document between runs.
///
/// A file the reader picks is copied into the app's own storage before the
/// desk ever sees it, because the reference a picker hands over is a loan:
/// on Android it stops working when the app restarts, and the file behind it
/// can be moved or deleted by anything. A copy the app owns is a document the
/// app can promise to open again tomorrow. The list of copies is written to a
/// small JSON file beside them, and what the reader has done with each
/// document, where they got to, what they starred, what they threw away, is
/// written to a second one, so that closing the app costs nothing.
class LibraryCatalogue {
  LibraryCatalogue();

  static const _folder = 'imports';
  static const _exports = 'exports';
  static const _index = 'library.json';
  static const _state = 'state.json';
  static const _version = 1;

  /// What a file being written is called before it is a file.
  static const _draft = '.tmp';

  /// What the one it replaces is called afterwards.
  static const _kept = '.bak';

  Directory? _root;

  Future<Directory> _home() async {
    final cached = _root;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}${Platform.pathSeparator}$_folder');
    if (!await root.exists()) await root.create(recursive: true);
    return _root = root;
  }

  /// Where each document's saved edits are kept.
  Future<Directory> revisionsHome() async {
    final root = await _home();
    final dir = Directory('${root.parent.path}${Platform.pathSeparator}revisions');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _fileIn(Directory root, String name) =>
      File('${root.path}${Platform.pathSeparator}$name');

  /// A JSON object read from [name] in the app's storage, or from the copy
  /// kept beside it, or an empty one, which the caller treats as a fresh
  /// start rather than as an error to show.
  Future<Map<String, Object?>> _readObject(String name) async {
    final root = await _home();
    final live = await _readOne(_fileIn(root, name));
    if (live != null) return live;
    // The live file is missing or will not parse, which is exactly what a
    // write the system stopped part way through leaves behind. The copy
    // beside it is the last one that was whole.
    return await _readOne(_fileIn(root, '$name$_kept')) ?? <String, Object?>{};
  }

  /// One candidate file read, or null for anything that is not a JSON object.
  ///
  /// It catches everything, not just a malformed file. A read can fail for
  /// reasons that are not `FormatException`: bytes that are not text at all,
  /// a permission the platform withdrew, a file another process is holding.
  /// Each of those has the same right answer, which is to try the copy beside
  /// it and then start fresh.
  Future<Map<String, Object?>?> _readOne(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) return decoded;
    } on Object {
      // Damaged, unreadable, or not ours. Starting over loses at most a
      // reading position; refusing to start loses the app.
    }
    return null;
  }

  /// Writes [object] to [name] without ever leaving [name] half written.
  ///
  /// This is called from the lifecycle handler as the app goes to the
  /// background, which is the one moment the system is most likely to stop it
  /// mid sentence. Written straight onto the live file, a kill between the
  /// truncate and the last byte left invalid JSON, and invalid JSON reads
  /// back as a fresh start: the whole desk, every reading position, every dog
  /// ear and every saved signature, gone without a word.
  ///
  /// So the bytes go to a draft beside it first, and only a file that is
  /// already complete is ever moved into place. The one it replaces is kept,
  /// because the cheapest way to survive a torn write is to still be holding
  /// yesterday's.
  Future<void> _writeObject(String name, Map<String, Object?> object) async {
    final root = await _home();
    final file = _fileIn(root, name);
    final draft = _fileIn(root, '$name$_draft');
    // First, because nothing above may be touched until this has worked. A
    // disk that is full fails here, with the live file still standing.
    await draft.writeAsString(jsonEncode(object), flush: true);
    if (await file.exists()) await file.copy('${file.path}$_kept');
    // Moving a whole file into place is one operation the system either did
    // or did not do, so the live file is never half written. Windows refuses
    // to move onto a file that exists, and there the copy kept beside it is
    // what covers the instant in between.
    if (Platform.isWindows && await file.exists()) await file.delete();
    await draft.rename(file.path);
  }

  /// The documents brought in so far, newest first, skipping any whose copy
  /// has gone missing rather than putting a card on the desk that cannot
  /// open.
  Future<List<LibraryEntry>> load() async {
    final items = (await _readObject(_index))['imported'];
    if (items is! List<Object?>) return const <LibraryEntry>[];
    final entries = <LibraryEntry>[];
    for (final item in items) {
      if (item is! Map<String, Object?>) continue;
      final path = item['path'];
      final format = item['format'];
      final bytes = item['bytes'];
      if (path is! String || format is! String || bytes is! int) continue;
      final known = DocFormat.forExtension(format);
      if (known == null) continue;
      if (!await File(path).exists()) continue;
      final title = item['title'];
      entries.add(
        LibraryEntry(
          path: path,
          title: title is String && title.isNotEmpty
              ? title
              : LibraryEntry.titleFor(path),
          format: known,
          bytes: bytes,
          source: DocSource.file,
        ),
      );
    }
    return entries;
  }

  /// Writes the list of brought in documents, newest first.
  Future<void> save(Iterable<LibraryEntry> imported) async {
    await _writeObject(_index, <String, Object?>{
      'version': _version,
      'imported': <Object?>[
        for (final entry in imported)
          if (entry.source == DocSource.file)
            <String, Object?>{
              'path': entry.path,
              'title': entry.title,
              'format': entry.format.extension,
              'bytes': entry.bytes,
            },
      ],
    });
  }

  /// What the desk remembered last time, as it was written by [saveState].
  Future<Map<String, Object?>> loadState() => _readObject(_state);

  /// Writes what the desk remembers. The shape is the desk's business; this
  /// only promises to hand the same object back.
  Future<void> saveState(Map<String, Object?> state) =>
      _writeObject(_state, <String, Object?>{'version': _version, ...state});

  /// Writes [bytes] into the app's storage under [name] and describes the
  /// result, or returns null for a file quire does not read.
  ///
  /// Bytes rather than a path, because the phone's picker does not always
  /// hand over a path: on Android it hands over a content reference that
  /// only the picker's own session can read, and the bytes are the one thing
  /// every platform can give. The copy keeps the original's name behind a
  /// timestamp, so two files called `notes.md` from two folders both survive,
  /// and the desk still shows each as Notes.
  Future<LibraryEntry?> import(String name, Uint8List bytes) async {
    final clean = name.replaceAll(RegExp(r'[\\/]+'), '_');
    final dot = clean.lastIndexOf('.');
    final format =
        dot < 0 ? null : DocFormat.forExtension(clean.substring(dot + 1));
    if (format == null) return null;
    final root = await _home();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final copy = _fileIn(root, '${stamp}_$clean');
    await copy.writeAsBytes(bytes, flush: true);
    return LibraryEntry(
      path: copy.path,
      title: LibraryEntry.titleFor(clean),
      format: format,
      bytes: bytes.length,
      source: DocSource.file,
    );
  }

  /// Writes [bytes] as [name] in a folder other apps can be handed files
  /// from, replacing an earlier export of the same name.
  Future<File> writeExport(String name, Uint8List bytes) async {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}${Platform.pathSeparator}$_exports');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = _fileIn(folder, name);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Deletes the copy behind [entry], for a document taken off the desk for
  /// good. A shipped document has no copy and nothing happens.
  Future<void> forget(LibraryEntry entry) async {
    if (entry.source != DocSource.file) return;
    final file = File(entry.path);
    if (await file.exists()) await file.delete();
  }
}
