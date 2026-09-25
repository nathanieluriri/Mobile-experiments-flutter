import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/services/revisions.dart';

Uint8List _b(List<int> v) => Uint8List.fromList(v);

void main() {
  late Directory root;
  late RevisionStore store;
  var tick = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('revisions');
    tick = 0;
    store = RevisionStore(
      () async => root,
      maxCount: 4,
      maxBytes: 100,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000 * ++tick),
    );
  });

  tearDown(() => root.delete(recursive: true));

  Future<Uint8List> original() async => _b([0]);
  const path = 'assets/documents/field_guide.md';

  test('a document nobody saved is read as it arrived', () async {
    expect(await store.currentBytes(path), isNull);
    expect((await store.history(path)).edited, isFalse);
  });

  test('a save is what is read next, and the one before is kept', () async {
    await store.save(path, _b([1]));
    await store.save(path, _b([2]), note: 'second');
    expect(await store.currentBytes(path), [2]);
    final history = await store.history(path);
    expect(history.current, 2);
    expect(history.revisions.map((r) => r.number), [1, 2]);
    expect(history.revisions.last.note, 'second');
    expect(await store.bytesOf(path, 1, original), [1]);
    expect(await store.bytesOf(path, 0, original), [0]);
  });

  test('restoring writes the old one again as the newest', () async {
    await store.save(path, _b([1]));
    await store.save(path, _b([2]));
    await store.restore(path, 0, original);
    final history = await store.history(path);
    expect(history.revisions.map((r) => r.number), [1, 2, 3]);
    expect(await store.currentBytes(path), [0]);
  });

  test('deleting the one being read moves back to the newest left', () async {
    await store.save(path, _b([1]));
    await store.save(path, _b([2]));
    await store.delete(path, 2);
    expect(await store.currentBytes(path), [1]);
    await store.delete(path, 1);
    expect(await store.currentBytes(path), isNull);
    expect((await store.history(path)).revisions, isEmpty);
  });

  test('forgetting keeps only the one being read', () async {
    await store.save(path, _b([1]));
    await store.save(path, _b([2]));
    await store.save(path, _b([3]));
    await store.forgetOthers(path);
    final history = await store.history(path);
    expect(history.revisions.map((r) => r.number), [3]);
    expect(await store.currentBytes(path), [3]);
    final files = root.listSync(recursive: true).whereType<File>();
    expect(files.where((f) => f.path.endsWith('r1') || f.path.endsWith('r2')), isEmpty);
  });

  test('old ones go by count, oldest first', () async {
    for (var i = 1; i <= 6; i++) {
      await store.save(path, _b([i]));
    }
    final history = await store.history(path);
    expect(history.revisions.map((r) => r.number), [3, 4, 5, 6]);
    expect(await store.bytesOf(path, 6, original), [6]);
  });

  test('old ones go by size, but never the one being read', () async {
    await store.save(path, Uint8List(60));
    await store.save(path, Uint8List(60));
    expect((await store.history(path)).revisions.map((r) => r.number), [2]);
    await store.save(path, Uint8List(500));
    final history = await store.history(path);
    expect(history.revisions.map((r) => r.number), [3]);
    expect(history.current, 3);
  });

  test('numbers are never used twice', () async {
    await store.save(path, _b([1]));
    await store.save(path, _b([2]));
    await store.delete(path, 2);
    await store.save(path, _b([3]));
    expect((await store.history(path)).revisions.map((r) => r.number), [1, 3]);
  });

  test('saves made at once all land', () async {
    await Future.wait([
      for (var i = 1; i <= 3; i++) store.save(path, _b([i])),
    ]);
    expect((await store.history(path)).revisions, hasLength(3));
  });

  test('a damaged manifest reads as the original', () async {
    await store.save(path, _b([1]));
    final manifest = root
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('manifest.json'));
    await manifest.writeAsString('{not json');
    expect(await store.currentBytes(path), isNull);
  });

  test('each document has its own history, and dropping one leaves the rest',
      () async {
    await store.save(path, _b([1]));
    await store.save('other.csv', _b([9]));
    await store.drop(path);
    expect(await store.currentBytes(path), isNull);
    expect(await store.currentBytes('other.csv'), [9]);
  });
}
