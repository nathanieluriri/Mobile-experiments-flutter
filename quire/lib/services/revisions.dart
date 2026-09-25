import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../pdf/crypt.dart' show md5;

/// One saved version of a document.
class Revision {
  const Revision({
    required this.number,
    required this.created,
    required this.size,
    this.note = '',
  });

  /// Counts up from 1 and is never reused. Revision 0 is the original.
  final int number;
  final DateTime created;
  final int size;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'n': number,
        'created': created.millisecondsSinceEpoch,
        'size': size,
        if (note.isNotEmpty) 'note': note,
      };

  static Revision? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final n = json['n'], created = json['created'], size = json['size'];
    if (n is! int || n < 1 || created is! int || size is! int) return null;
    final note = json['note'];
    return Revision(
      number: n,
      created: DateTime.fromMillisecondsSinceEpoch(created),
      size: size,
      note: note is String ? note : '',
    );
  }
}

/// A document's history: what it was when it arrived, and every save since.
class History {
  const History(this.current, this.revisions);

  /// The revision the reader is reading, or 0 for the original.
  final int current;

  /// Oldest first. The original is not among them: it is never stored, since
  /// it is the shipped file, the imported copy or the file on the phone, and
  /// it is never deleted.
  final List<Revision> revisions;

  bool get edited => current != 0;

  static const empty = History(0, <Revision>[]);
}

/// Every edit the reader saves, kept beside the document rather than over it.
///
/// A save writes a new revision and points the document at it. Reading an
/// older one points the document back at it and writes nothing, so going
/// back and forth makes no revisions; the next save after it becomes the
/// newest. Old revisions are dropped oldest first once there are more than
/// [maxCount] or they take more than [maxBytes], but never the one being
/// read.
class RevisionStore {
  RevisionStore(
    this._home, {
    this.maxCount = 20,
    this.maxBytes = 100 * 1024 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _home;
  final int maxCount;
  final int maxBytes;
  final DateTime Function() _clock;

  static const _manifest = 'manifest.json';

  /// One operation at a time per document, so two saves cannot both read the
  /// same manifest and each write back half the story.
  final Map<String, Future<void>> _queue = <String, Future<void>>{};

  Future<T> _serial<T>(String path, Future<T> Function() run) {
    final before = _queue[path] ?? Future<void>.value();
    final done = Completer<T>();
    final next = before.then((_) async {
      try {
        done.complete(await run());
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    _queue[path] = next;
    unawaited(next.whenComplete(() {
      if (identical(_queue[path], next)) _queue.remove(path);
    }));
    return done.future;
  }

  static String _key(String path) => md5(Uint8List.fromList(utf8.encode(path)))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  Future<Directory> _folder(String path, {bool make = false}) async {
    final root = await _home();
    final dir = Directory('${root.path}${Platform.pathSeparator}${_key(path)}');
    if (make && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  File _revisionFile(Directory dir, int n) => _file(dir, 'r$n');

  Future<(History, int)> _read(Directory dir) async {
    try {
      final file = _file(dir, _manifest);
      if (!await file.exists()) return (History.empty, 1);
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return (History.empty, 1);
      final list = <Revision>[
        for (final item in (json['revisions'] as List<Object?>?) ?? const [])
          ?Revision.fromJson(item),
      ];
      final current = json['current'];
      final next = json['next'];
      final known = list.any((r) => r.number == current);
      return (
        History(known ? current! as int : 0, list),
        next is int ? next : (list.isEmpty ? 1 : list.last.number + 1),
      );
    } on Object {
      // A manifest that cannot be read is a document read as it arrived,
      // which is always there to read.
      return (History.empty, 1);
    }
  }

  Future<void> _write(Directory dir, History history, int next) async {
    final file = _file(dir, _manifest);
    final draft = _file(dir, '$_manifest.tmp');
    await draft.writeAsString(
      jsonEncode(<String, Object?>{
        'current': history.current,
        'next': next,
        'revisions': [for (final r in history.revisions) r.toJson()],
      }),
      flush: true,
    );
    if (Platform.isWindows && await file.exists()) await file.delete();
    await draft.rename(file.path);
  }

  /// [path]'s history.
  Future<History> history(String path) => _serial(path, () async {
        return (await _read(await _folder(path))).$1;
      });

  /// The bytes of the revision [path] is being read at, or null when that
  /// is the original.
  Future<Uint8List?> currentBytes(String path) =>
      _serial(path, () async {
        final dir = await _folder(path);
        final (history, _) = await _read(dir);
        if (!history.edited) return null;
        try {
          return await _revisionFile(dir, history.current).readAsBytes();
        } on FileSystemException {
          return null;
        }
      });

  /// The bytes of revision [number] of [path], with [original] asked for
  /// revision 0.
  Future<Uint8List> bytesOf(
    String path,
    int number,
    Future<Uint8List> Function() original,
  ) async {
    if (number == 0) return original();
    final dir = await _folder(path);
    return _revisionFile(dir, number).readAsBytes();
  }

  /// Saves [bytes] as the newest revision of [path] and reads from it.
  Future<Revision> save(String path, Uint8List bytes, {String note = ''}) =>
      _serial(path, () => _save(path, bytes, note));

  Future<Revision> _save(String path, Uint8List bytes, String note) async {
    final dir = await _folder(path, make: true);
    final (history, next) = await _read(dir);
    final file = _revisionFile(dir, next);
    final draft = _file(dir, 'r$next.tmp');
    // The revision is whole on disk before the manifest names it, so a save
    // cut short leaves the document at the revision it was at.
    await draft.writeAsBytes(bytes, flush: true);
    await draft.rename(file.path);
    final made = Revision(
      number: next,
      created: _clock(),
      size: bytes.length,
      note: note,
    );
    final kept = await _prune(dir, [...history.revisions, made], next);
    await _write(dir, History(next, kept), next + 1);
    return made;
  }

  /// Reads [path] from revision [number] from now on, 0 being the original,
  /// without writing anything new.
  Future<void> readFrom(String path, int number) => _serial(path, () async {
        final dir = await _folder(path);
        final (history, next) = await _read(dir);
        if (number != 0 && !history.revisions.any((r) => r.number == number)) return;
        if (number == history.current) return;
        await _write(dir, History(number, history.revisions), next);
      });

  /// Removes revision [number]. Removing the one being read moves the reader
  /// to the newest that is left, or to the original.
  Future<void> delete(String path, int number) => _serial(path, () async {
        final dir = await _folder(path);
        final (history, next) = await _read(dir);
        final kept = [
          for (final r in history.revisions)
            if (r.number != number) r,
        ];
        if (kept.length == history.revisions.length) return;
        final current = history.current == number
            ? (kept.isEmpty ? 0 : kept.last.number)
            : history.current;
        await _write(dir, History(current, kept), next);
        await _gone(_revisionFile(dir, number));
      });

  /// Removes every revision but the one being read. The original stays too.
  Future<void> forgetOthers(String path) => _serial(path, () async {
        final dir = await _folder(path);
        final (history, next) = await _read(dir);
        final kept = [
          for (final r in history.revisions)
            if (r.number == history.current) r,
        ];
        await _write(dir, History(history.current, kept), next);
        for (final r in history.revisions) {
          if (r.number != history.current) {
            await _gone(_revisionFile(dir, r.number));
          }
        }
      });

  /// Removes [path]'s whole history, for a document deleted for good.
  Future<void> drop(String path) => _serial(path, () async {
        final dir = await _folder(path);
        if (await dir.exists()) await dir.delete(recursive: true);
      });

  Future<List<Revision>> _prune(
    Directory dir,
    List<Revision> all,
    int current,
  ) async {
    final kept = List<Revision>.of(all);
    var total = kept.fold<int>(0, (sum, r) => sum + r.size);
    while (kept.length > 1 && (kept.length > maxCount || total > maxBytes)) {
      final oldest = kept.firstWhere((r) => r.number != current);
      kept.remove(oldest);
      total -= oldest.size;
      await _gone(_revisionFile(dir, oldest.number));
    }
    return kept;
  }

  static Future<void> _gone(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A revision no manifest names is only space, and the next prune or
      // drop of the folder takes it.
    }
  }
}
