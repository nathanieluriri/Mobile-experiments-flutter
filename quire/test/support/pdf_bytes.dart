import 'dart:convert';
import 'dart:typed_data';

/// Assembles a small but genuine PDF: header, numbered objects, a classic
/// cross reference table with real offsets, a trailer and startxref.
///
/// The engine's harder paths (a lying /Length, an invisible render mode, an
/// /ExtGState alpha, an indexed image) cannot be reached from the two bundled
/// documents, and a fixture file checked into the repo would hide what it is
/// testing inside a blob. Building the bytes in the test states the case in
/// the open.
Uint8List buildPdf(List<List<int>> objects, {String trailerExtra = ''}) {
  final out = <int>[];
  void add(String s) => out.addAll(ascii.encode(s));
  add('%PDF-1.7\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    add('${i + 1} 0 obj\n');
    out.addAll(objects[i]);
    add('\nendobj\n');
  }
  final xrefAt = out.length;
  add('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    add('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  add('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R $trailerExtra>>\n');
  add('startxref\n$xrefAt\n%%EOF\n');
  return Uint8List.fromList(out);
}

List<int> obj(String body) => ascii.encode(body);

/// A stream object. [lengthOverride] writes a /Length the data does not have,
/// which is how a producer that miscounts its own stream is simulated.
List<int> streamObj(String dict, List<int> data, {int? lengthOverride}) => [
      ...ascii.encode('<< $dict /Length ${lengthOverride ?? data.length} >>\n'
          'stream\n'),
      ...data,
      ...ascii.encode('\nendstream'),
    ];
