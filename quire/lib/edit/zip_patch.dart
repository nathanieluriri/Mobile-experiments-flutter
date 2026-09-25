import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;

/// Thrown when a package cannot be patched in place: it is not a zip this
/// reader understands the layout of, such as one that needs ZIP64.
class ZipPatchError implements Exception {
  const ZipPatchError(this.message);
  final String message;
  @override
  String toString() => 'ZipPatchError: $message';
}

class _Entry {
  _Entry(this.record, this.name, this.offset);

  /// The central directory record as it stands in the file.
  final Uint8List record;
  final String name;
  final int offset;
  int end = 0;
}

/// [original] with the parts in [replace] swapped for new contents, and every
/// other part copied across byte for byte: its local header, its compressed
/// data, its descriptor, all as they were.
///
/// An Office file is a zip of XML parts, and quire understands only some of
/// them. Anything it does not model survives an edit because it is never
/// decompressed, never parsed and never written again: the bytes that come
/// out are the bytes that went in. Only a replaced part is compressed afresh.
///
/// A part named in [replace] that the package does not hold is added at the
/// end, and a part named in [remove] is left out.
Uint8List patchZip(
  Uint8List original,
  Map<String, List<int>> replace, {
  Set<String> remove = const <String>{},
}) {
  if (replace.isEmpty && remove.isEmpty) return original;
  final data = ByteData.sublistView(original);

  // The end of central directory record, searched for from the end, past a
  // comment of up to 64K.
  var eocd = -1;
  final floor = original.length - 22 - 0xFFFF;
  for (var i = original.length - 22; i >= 0 && i >= floor; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const ZipPatchError('no end of central directory');
  final count = data.getUint16(eocd + 10, Endian.little);
  final cdSize = data.getUint32(eocd + 12, Endian.little);
  final cdOffset = data.getUint32(eocd + 16, Endian.little);
  if (count == 0xFFFF || cdOffset == 0xFFFFFFFF) {
    throw const ZipPatchError('ZIP64 is not patched in place');
  }
  if (cdOffset + cdSize > eocd) {
    throw const ZipPatchError('the central directory runs past its end');
  }

  final entries = <_Entry>[];
  var at = cdOffset;
  for (var i = 0; i < count; i++) {
    if (at + 46 > original.length ||
        data.getUint32(at, Endian.little) != 0x02014b50) {
      throw const ZipPatchError('a broken central directory record');
    }
    final nameLength = data.getUint16(at + 28, Endian.little);
    final extraLength = data.getUint16(at + 30, Endian.little);
    final commentLength = data.getUint16(at + 32, Endian.little);
    final offset = data.getUint32(at + 42, Endian.little);
    final length = 46 + nameLength + extraLength + commentLength;
    if (at + length > original.length) {
      throw const ZipPatchError('a record runs past the end');
    }
    final name = utf8.decode(
      original.sublist(at + 46, at + 46 + nameLength),
      allowMalformed: true,
    );
    entries.add(
      _Entry(Uint8List.fromList(original.sublist(at, at + length)), name, offset),
    );
    at += length;
  }

  // Each entry's bytes run from its local header to the next one's, or to the
  // central directory, which takes in a data descriptor where there is one.
  final byOffset = List<_Entry>.of(entries)
    ..sort((a, b) => a.offset.compareTo(b.offset));
  for (var i = 0; i < byOffset.length; i++) {
    byOffset[i].end =
        i + 1 < byOffset.length ? byOffset[i + 1].offset : cdOffset;
    if (byOffset[i].end < byOffset[i].offset) {
      throw const ZipPatchError('entries overlap');
    }
  }

  final out = BytesBuilder(copy: false);
  final newOffsets = <_Entry, int>{};
  final written = <_Entry, (int crc, int compressed, int size)>{};
  for (final entry in byOffset) {
    if (remove.contains(entry.name)) continue;
    newOffsets[entry] = out.length;
    final content = replace[entry.name];
    if (content == null) {
      out.add(Uint8List.sublistView(original, entry.offset, entry.end));
      continue;
    }
    final compressed = ZLibCodec(raw: true, level: 6).encode(content);
    final crc = getCrc32(content);
    written[entry] = (crc, compressed.length, content.length);
    final record = ByteData.sublistView(entry.record);
    out.add(_localHeader(
      name: entry.record.sublist(46, 46 + record.getUint16(28, Endian.little)),
      flags: record.getUint16(8, Endian.little) & 0x0800,
      time: record.getUint16(12, Endian.little),
      date: record.getUint16(14, Endian.little),
      crc: crc,
      compressed: compressed.length,
      size: content.length,
    ));
    out.add(compressed);
  }

  // Parts to add, after everything that was there.
  final added = <(Uint8List name, int offset, int crc, int compressed, int size)>[];
  final held = {for (final entry in entries) entry.name};
  for (final part in replace.entries) {
    if (held.contains(part.key) || remove.contains(part.key)) continue;
    final name = Uint8List.fromList(utf8.encode(part.key));
    final compressed = ZLibCodec(raw: true, level: 6).encode(part.value);
    final crc = getCrc32(part.value);
    added.add((name, out.length, crc, compressed.length, part.value.length));
    out.add(_localHeader(
      name: name,
      flags: 0x0800,
      time: 0,
      date: 0x21,
      crc: crc,
      compressed: compressed.length,
      size: part.value.length,
    ));
    out.add(compressed);
  }

  final newCdOffset = out.length;
  final kept = <_Entry>[
    for (final entry in entries)
      if (!remove.contains(entry.name)) entry,
  ];
  for (final entry in kept) {
    final record = Uint8List.fromList(entry.record);
    final fields = ByteData.sublistView(record);
    fields.setUint32(42, newOffsets[entry]!, Endian.little);
    final fresh = written[entry];
    if (fresh != null) {
      final (crc, compressed, size) = fresh;
      fields
        ..setUint16(8, fields.getUint16(8, Endian.little) & 0x0800, Endian.little)
        ..setUint16(10, 8, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, compressed, Endian.little)
        ..setUint32(24, size, Endian.little);
    }
    out.add(record);
  }
  for (final (name, offset, crc, compressed, size) in added) {
    final record = ByteData(46);
    record
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, 8, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, compressed, Endian.little)
      ..setUint32(24, size, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    out
      ..add(record.buffer.asUint8List())
      ..add(name);
  }
  final newCdSize = out.length - newCdOffset;

  final end = Uint8List.fromList(original.sublist(eocd));
  final tail = ByteData.sublistView(end);
  final total = kept.length + added.length;
  tail
    ..setUint16(8, total, Endian.little)
    ..setUint16(10, total, Endian.little)
    ..setUint32(12, newCdSize, Endian.little)
    ..setUint32(16, newCdOffset, Endian.little);
  out.add(end);
  return out.takeBytes();
}

Uint8List _localHeader({
  required List<int> name,
  required int flags,
  required int time,
  required int date,
  required int crc,
  required int compressed,
  required int size,
}) {
  final header = ByteData(30);
  header
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, flags, Endian.little)
    ..setUint16(8, 8, Endian.little)
    ..setUint16(10, time, Endian.little)
    ..setUint16(12, date, Endian.little)
    ..setUint32(14, crc, Endian.little)
    ..setUint32(18, compressed, Endian.little)
    ..setUint32(22, size, Endian.little)
    ..setUint16(26, name.length, Endian.little)
    ..setUint16(28, 0, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(name))
      .takeBytes();
}
