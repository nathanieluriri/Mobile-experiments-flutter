import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quire/data/library.dart';
import 'package:quire/services/document_store.dart';

/// A CSV of about [megabytes] megabytes, written to a folder of its own.
Future<LibraryEntry> _largeCsv(Directory dir, {int megabytes = 7}) async {
  final file = File('${dir.path}/ledger.csv');
  final sink = file.openWrite();
  sink.writeln('date,account,memo,debit,credit,balance');
  var written = 0;
  for (var row = 0; written < megabytes * 1024 * 1024; row++) {
    final line = '2026-09-${(row % 28 + 1).toString().padLeft(2, '0')},'
        'ACC-${row % 97},"payment $row for stock",${row % 1000}.25,0,'
        '${row * 3}.75';
    sink.writeln(line);
    written += line.length + 1;
  }
  await sink.close();
  return LibraryEntry.imported(
    path: file.path,
    format: DocFormat.csv,
    bytes: file.lengthSync(),
  );
}

/// The longest the event loop went without running a 16ms timer while
/// [work] was under way.
Future<Duration> _longestStall(Future<void> Function() work) async {
  var last = DateTime.now();
  var longest = Duration.zero;
  final ticks = Timer.periodic(const Duration(milliseconds: 16), (_) {
    final now = DateTime.now();
    final gap = now.difference(last);
    if (gap > longest) longest = gap;
    last = now;
  });
  await work();
  final gap = DateTime.now().difference(last);
  if (gap > longest) longest = gap;
  ticks.cancel();
  return longest;
}

void main() {
  late Directory dir;
  late LibraryEntry entry;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('quire_parse');
    entry = await _largeCsv(dir);
  });

  tearDownAll(() async {
    DocumentStore.parseInBackground = false;
    await dir.delete(recursive: true);
  });

  test('reading a large file leaves the frames running', () async {
    DocumentStore.parseInBackground = true;
    final library = LibraryStore(entries: [entry]);
    final stall = await _longestStall(library.hydrate);
    final store = library.storeFor(entry);
    expect(store.state, ParseState.ready);
    expect(store.unitCount, greaterThan(100000));
    // A frame is 16ms. Copying the bytes to the isolate and back is the only
    // work left here, and it is a small fraction of the parse.
    expect(stall, lessThan(const Duration(milliseconds: 250)));
  });

  test('the same read on the main isolate stalls it, which is the point', () async {
    DocumentStore.parseInBackground = false;
    final library = LibraryStore(entries: [entry]);
    final stall = await _longestStall(library.hydrate);
    expect(library.storeFor(entry).state, ParseState.ready);
    expect(stall, greaterThan(const Duration(milliseconds: 250)));
  });

  test('a file that fails in the isolate comes back as failed', () async {
    DocumentStore.parseInBackground = true;
    final file = File('${dir.path}/broken.docx')
      ..writeAsBytesSync(List<int>.generate(4096, (i) => i * 7 % 251));
    final broken = LibraryEntry.imported(
      path: file.path,
      format: DocFormat.docx,
      bytes: 4096,
    );
    final library = LibraryStore(entries: [broken]);
    await library.hydrate();
    final store = library.storeFor(broken);
    expect(store.state, ParseState.failed);
    expect(store.bytes.length, 4096);
  });

  test('a PDF read in the isolate keeps its open file and its count', () async {
    DocumentStore.parseInBackground = true;
    final source = File('assets/documents/field-guide-to-paper.pdf');
    final copy = File('${dir.path}/guide.pdf')
      ..writeAsBytesSync(source.readAsBytesSync());
    final pdf = LibraryEntry.imported(
      path: copy.path,
      format: DocFormat.pdf,
      bytes: copy.lengthSync(),
    );
    final library = LibraryStore(entries: [pdf]);
    await library.hydrate();
    final store = library.storeFor(pdf);
    expect(store.state, ParseState.ready);
    expect(store.pdfPageCount, 6);
    expect(store.pdf, isNotNull);
  });

  test('two asks for the same document share one read', () async {
    DocumentStore.parseInBackground = true;
    final library = LibraryStore(entries: [entry]);
    await Future.wait([library.hydrate(), library.hydrate()]);
    expect(library.storeFor(entry).state, ParseState.ready);
  });
}
