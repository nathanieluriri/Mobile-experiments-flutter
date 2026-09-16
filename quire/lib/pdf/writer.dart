import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:archive/archive.dart';

import 'document.dart';
import 'lexer.dart' show PdfKeyword;
import 'objects.dart';

/// A picture on its way into a page: colour and opacity kept apart, which is
/// how the format wants them.
class PdfImage {
  const PdfImage({
    required this.width,
    required this.height,
    required this.rgb,
    this.alpha,
  });

  final int width;
  final int height;

  /// Three bytes a pixel, row by row from the top.
  final Uint8List rgb;

  /// One byte a pixel in the same order, or null for a picture with nothing
  /// transparent in it, which then needs no mask at all.
  final Uint8List? alpha;
}

/// A mark to set into a page: which page, where on it, and its ribbons.
///
/// [rect] is stated the way the reader states it, in the page's own points
/// with the origin at the top left of the box the page is drawn in, and each
/// outline is a closed polygon in the unit square of that rect. The writer
/// turns both into the page's user space, which has its origin at the bottom
/// left and its y running up.
class PlacedInk {
  const PlacedInk({
    required this.pageIndex,
    required this.rect,
    required this.outlines,
    this.image,
  });

  final int pageIndex;
  final Rect rect;
  final List<List<Offset>> outlines;

  /// The picture this mark is, for a mark that is one. A mark carries either
  /// ribbons or a picture, never both.
  final PdfImage? image;
}

/// Why a file could not be written, in words a reader can be shown.
class PdfWriteError implements Exception {
  const PdfWriteError(this.message);
  final String message;
  @override
  String toString() => 'PdfWriteError: $message';
}

/// Writes signatures into a PDF as an incremental update.
///
/// Nothing in the original file is touched. The new file is the old bytes
/// followed by a few new objects, a new cross reference section and a new
/// trailer, which is the one way of changing a PDF that the format itself
/// designed for: every earlier viewer, every signature already in the file
/// and every byte a checksum was taken over is exactly where it was.
///
/// Each signed page gets its content wrapped: a stream holding `q` before the
/// page's own content and, after it, a stream holding `Q` and the ink. The
/// `Q` puts the graphics state back to what the page started with, so a page
/// that ended inside a transform still takes the ink where it was placed.
/// The ink is the ribbons the reader drew, filled as polygons, which is the
/// same shape the screen showed and not an approximation of it.
class PdfSignatureWriter {
  PdfSignatureWriter._(this.file)
      : _next = _firstFreeNumber(file),
        _out = BytesBuilder(copy: false);

  final PdfFile file;
  int _next;
  final BytesBuilder _out;

  /// New objects by number, each already serialised in full.
  final Map<int, Uint8List> _objects = <int, Uint8List>{};

  /// The generation each new object number carries: 0 for a fresh object,
  /// and the page's own for a page written again.
  final Map<int, int> _generations = <int, int>{};

  /// The whole file with [marks] set into its pages.
  static Uint8List signed(PdfFile file, List<PlacedInk> marks) {
    if (marks.isEmpty) {
      throw const PdfWriteError('There is no signature to write.');
    }
    if (file.recoveredByScan) {
      throw const PdfWriteError(
        'This file is too damaged to sign without rewriting it.',
      );
    }
    if (file.startxref <= 0) {
      throw const PdfWriteError('This file has no cross reference to add to.');
    }
    for (final mark in marks) {
      // A mark with nothing to draw would come out as a file that says it is
      // signed and is not, which is worse than no file at all.
      if (mark.image == null && !mark.outlines.any((o) => o.length >= 3)) {
        throw const PdfWriteError('A signature has no ink to write.');
      }
    }
    return PdfSignatureWriter._(file)._write(marks);
  }

  static int _firstFreeNumber(PdfFile file) {
    var next = 1;
    for (final number in file.xref.keys) {
      if (number >= next) next = number + 1;
    }
    final size = file.resolve(file.trailer['Size']);
    if (size is int && size > next) next = size;
    return next;
  }

  Uint8List _write(List<PlacedInk> marks) {
    final byPage = <int, List<PlacedInk>>{};
    for (final mark in marks) {
      byPage.putIfAbsent(mark.pageIndex, () => <PlacedInk>[]).add(mark);
    }
    for (final entry in byPage.entries) {
      _signPage(entry.key, entry.value);
    }

    // The original, then a line break in case it ended without one, then
    // every new object at an offset the cross reference can point at.
    _out.add(file.bytes);
    _out.add(const <int>[0x0a]);
    final offsets = <int, int>{};
    final numbers = _objects.keys.toList()..sort();
    for (final number in numbers) {
      offsets[number] = _out.length;
      _out.add(_objects[number]!);
    }
    final startxref = _out.length;
    if (file.xrefIsStream) {
      _xrefStream(offsets);
    } else {
      _xrefTable(offsets);
    }
    _out.add(ascii.encode('startxref\n$startxref\n%%EOF\n'));
    return _out.takeBytes();
  }

  // --------------------------------------------------------------- pages

  void _signPage(int index, List<PlacedInk> marks) {
    final pages = file.pages;
    if (index < 0 || index >= pages.length) {
      throw PdfWriteError('Page ${index + 1} is not in this file.');
    }
    final ref = file.pageRefs[index];
    if (ref == null) {
      throw const PdfWriteError('This page cannot be found in the file.');
    }
    final page = pages[index];
    final box = _boxOf(page);

    // Every picture on this page becomes an object of its own, named so the
    // content stream can call for it.
    final names = <PlacedInk, String>{};
    final xobjects = <String, Object?>{};
    for (final mark in marks) {
      final image = mark.image;
      if (image == null) continue;
      final name = 'QuireSig$_next';
      names[mark] = name;
      xobjects[name] = PdfRef(_addImage(image), 0);
    }

    final ink = _inkStream(box, marks, names);
    final inkNumber = _add(_stream(_next, 0, ink));

    final contents = file.resolve(page['Contents']);
    final chain = <Object?>[];
    if (contents != null) {
      final q = _add(_stream(_next, 0, ascii.encode('q\n')));
      chain.add(PdfRef(q, 0));
      if (contents is List) {
        chain.addAll(contents);
      } else {
        chain.add(page['Contents']);
      }
    }
    chain.add(PdfRef(inkNumber, 0));

    final dict = Map<String, Object?>.of(page)
      ..['Contents'] = chain
      ..['Resources'] =
          xobjects.isEmpty ? page['Resources'] : _resourcesWith(page, xobjects);
    _objects[ref.number] = _serialiseObject(ref.number, ref.generation, dict);
    _generations[ref.number] = ref.generation;
  }

  /// The box the reader drew the page in, the same way the interpreter picks
  /// it: the crop box when there is a sane one, else the media box.
  List<double> _boxOf(Map<String, Object?> page) {
    var box = file.mediaBox(page);
    final crop = file.resolve(page['CropBox']);
    if (crop is List && crop.length == 4) {
      final values = <double>[];
      for (final value in crop) {
        final n = file.resolve(value);
        values.add(n is num ? n.toDouble() : 0);
      }
      box = values;
    }
    return box;
  }

  /// The page's resources with [xobjects] added.
  ///
  /// A fresh dictionary rather than a change to the one that is there, because
  /// a resource dictionary is very often shared by every page in the file, and
  /// adding this page's signature to it would put that signature on all of
  /// them. Whatever the page already had is carried across as it stands, refs
  /// and all.
  Map<String, Object?> _resourcesWith(
    Map<String, Object?> page,
    Map<String, Object?> xobjects,
  ) {
    final existing = file.dict(page['Resources']) ?? const <String, Object?>{};
    final merged = Map<String, Object?>.of(existing);
    final had = file.dict(existing['XObject']);
    merged['XObject'] = <String, Object?>{...?had, ...xobjects};
    return merged;
  }

  /// Writes [image] and its mask, and returns the picture's object number.
  int _addImage(PdfImage image) {
    final alpha = image.alpha;
    var maskNumber = 0;
    if (alpha != null) {
      maskNumber = _add(
        _imageStream(
          _next,
          data: alpha,
          width: image.width,
          height: image.height,
          grey: true,
          smask: 0,
        ),
      );
    }
    return _add(
      _imageStream(
        _next,
        data: image.rgb,
        width: image.width,
        height: image.height,
        grey: false,
        smask: maskNumber,
      ),
    );
  }

  /// One image object, deflated.
  ///
  /// A signature is mostly paper, so it compresses to a fraction of itself,
  /// and a file nobody can send is a file nobody has signed.
  Uint8List _imageStream(
    int number, {
    required Uint8List data,
    required int width,
    required int height,
    required bool grey,
    required int smask,
  }) {
    final deflated = Uint8List.fromList(const ZLibEncoder().encodeBytes(data));
    final body = file.encryptForObject(deflated, number, 0);
    final dict = StringBuffer()
      ..write('<< /Type /XObject /Subtype /Image')
      ..write(' /Width $width /Height $height')
      ..write(grey ? ' /ColorSpace /DeviceGray' : ' /ColorSpace /DeviceRGB')
      ..write(' /BitsPerComponent 8 /Filter /FlateDecode')
      ..write(' /Length ${body.length}');
    if (smask > 0) dict.write(' /SMask $smask 0 R');
    dict.write(' >>');
    final head = ascii.encode('$number 0 obj\n$dict\nstream\n');
    final tail = ascii.encode('\nendstream\nendobj\n');
    return Uint8List.fromList(<int>[...head, ...body, ...tail]);
  }

  /// The content that draws [marks], in the page's user space.
  Uint8List _inkStream(
    List<double> box,
    List<PlacedInk> marks,
    Map<PlacedInk, String> names,
  ) {
    final x0 = box[0] < box[2] ? box[0] : box[2];
    final y0 = box[1] < box[3] ? box[1] : box[3];
    final height = (box[3] - box[1]).abs();
    final top = y0 + height;
    final buffer = StringBuffer()
      ..writeln('Q')
      ..writeln('q')
      ..writeln('0.067 0.067 0.067 rg');
    for (final mark in marks) {
      final name = names[mark];
      if (name != null) {
        // A picture is placed by the matrix that maps the unit square onto
        // the box it was put in: width and height along the diagonal, the
        // bottom left corner in the translation.
        final left = x0 + mark.rect.left;
        final bottom = top - (mark.rect.top + mark.rect.height);
        buffer
          ..writeln('q')
          ..write(_num(mark.rect.width))
          ..write(' 0 0 ')
          ..write(_num(mark.rect.height))
          ..write(' ')
          ..write(_num(left))
          ..write(' ')
          ..write(_num(bottom))
          ..writeln(' cm')
          ..writeln('${_name(name)} Do')
          ..writeln('Q');
        continue;
      }
      var drew = false;
      for (final outline in mark.outlines) {
        if (outline.length < 3) continue;
        for (var i = 0; i < outline.length; i++) {
          final point = outline[i];
          final x = x0 + mark.rect.left + point.dx * mark.rect.width;
          final y = top - (mark.rect.top + point.dy * mark.rect.height);
          buffer
            ..write(_num(x))
            ..write(' ')
            ..write(_num(y))
            ..writeln(i == 0 ? ' m' : ' l');
        }
        buffer.writeln('h');
        drew = true;
      }
      if (drew) buffer.writeln('f');
    }
    buffer.writeln('Q');
    return ascii.encode(buffer.toString());
  }

  // ------------------------------------------------------------- objects

  /// Takes the next object number for [bytes] and returns it.
  int _add(Uint8List bytes) {
    final number = _next++;
    _objects[number] = bytes;
    _generations[number] = 0;
    return number;
  }

  /// A stream object holding [data], encrypted the way the file's other
  /// streams are when the file is encrypted.
  Uint8List _stream(int number, int generation, Uint8List data) {
    final body = file.encryptForObject(data, number, generation);
    final head = ascii.encode(
      '$number $generation obj\n<< /Length ${body.length} >>\nstream\n',
    );
    final tail = ascii.encode('\nendstream\nendobj\n');
    return Uint8List.fromList(<int>[...head, ...body, ...tail]);
  }

  Uint8List _serialiseObject(int number, int generation, Object? value) {
    final buffer = StringBuffer()..write('$number $generation obj\n');
    _serialise(buffer, value, number, generation, encrypt: true);
    buffer.write('\nendobj\n');
    return Uint8List.fromList(latin1.encode(buffer.toString()));
  }

  /// Writes [value]. Strings are encrypted only inside an ordinary object:
  /// the trailer and a cross reference stream are read before any key is
  /// known, so a string in either, the file identifier above all, has to be
  /// written exactly as it is.
  void _serialise(
    StringBuffer out,
    Object? value,
    int number,
    int gen, {
    required bool encrypt,
  }) {
    switch (value) {
      case null:
        out.write('null');
      case bool():
        out.write(value ? 'true' : 'false');
      case int():
        out.write(value);
      case double():
        out.write(_num(value));
      case PdfName():
        out.write(_name(value.value));
      case PdfRef():
        out.write('${value.number} ${value.generation} R');
      case PdfString():
        // Strings were read in clear, so a string that came out of an
        // encrypted file goes back in under the key of the object it is now
        // part of, which is what a viewer will decrypt it with.
        final bytes = encrypt
            ? file.encryptForObject(value.bytes, number, gen)
            : value.bytes;
        out.write('<');
        for (final b in bytes) {
          out.write(b.toRadixString(16).padLeft(2, '0'));
        }
        out.write('>');
      case List():
        out.write('[');
        for (var i = 0; i < value.length; i++) {
          if (i > 0) out.write(' ');
          _serialise(out, value[i], number, gen, encrypt: encrypt);
        }
        out.write(']');
      case Map<String, Object?>():
        // A key with nothing under it is a key the dictionary does not have.
        // The page tree walk leaves such keys behind for attributes a page
        // did not inherit, and writing them out would only be noise.
        out.write('<<');
        for (final entry in value.entries) {
          if (entry.value == null) continue;
          out
            ..write(' ')
            ..write(_name(entry.key))
            ..write(' ');
          _serialise(out, entry.value, number, gen, encrypt: encrypt);
        }
        out.write(' >>');
      case PdfKeyword(value: 'true' || 'false' || 'null'):
        out.write(value.value);
      case PdfStream():
        // A page dictionary never holds a stream inline; a file where one
        // does is not one this writer can promise to reproduce.
        throw const PdfWriteError('This page holds data that cannot be copied.');
      default:
        throw const PdfWriteError(
          'This file holds something quire cannot copy into a signed version.',
        );
    }
  }

  /// A name with every character the format reserves written as `#xx`.
  static String _name(String value) {
    final out = StringBuffer('/');
    for (final code in value.codeUnits) {
      final reserved = code < 0x21 ||
          code > 0x7e ||
          code == 0x23 || // #
          code == 0x2f || // /
          code == 0x25 || // %
          code == 0x28 || // (
          code == 0x29 || // )
          code == 0x3c || // <
          code == 0x3e || // >
          code == 0x5b || // [
          code == 0x5d || // ]
          code == 0x7b || // {
          code == 0x7d; // }
      if (reserved) {
        out.write('#${code.toRadixString(16).padLeft(2, '0')}');
      } else {
        out.writeCharCode(code);
      }
    }
    return out.toString();
  }

  /// A number the way the format likes them: no exponent, no trailing zeros.
  static String _num(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e9) {
      return value.toInt().toString();
    }
    var text = value.toStringAsFixed(4);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text == '-0' ? '0' : text;
  }

  // ---------------------------------------------------------------- xref

  /// The entries the new trailer carries over from the old one.
  Map<String, Object?> _trailer(int size) {
    final out = <String, Object?>{
      'Size': size,
      'Prev': file.startxref,
    };
    for (final key in const <String>['Root', 'Info', 'Encrypt', 'ID']) {
      final value = file.trailer[key];
      if (value != null) out[key] = value;
    }
    return out;
  }

  int get _size {
    var size = _next;
    for (final number in _objects.keys) {
      if (number >= size) size = number + 1;
    }
    return size;
  }

  /// A classic table, for a file whose own cross reference is one.
  void _xrefTable(Map<int, int> offsets) {
    final numbers = offsets.keys.toList()..sort();
    final buffer = StringBuffer()..writeln('xref');
    buffer
      ..writeln('0 1')
      ..write('0000000000 65535 f \n');
    var i = 0;
    while (i < numbers.length) {
      var j = i;
      while (j + 1 < numbers.length && numbers[j + 1] == numbers[j] + 1) {
        j++;
      }
      buffer.writeln('${numbers[i]} ${j - i + 1}');
      for (var k = i; k <= j; k++) {
        final number = numbers[k];
        buffer.write(
          '${offsets[number]!.toString().padLeft(10, '0')} '
          '${(_generations[number] ?? 0).toString().padLeft(5, '0')} n \n',
        );
      }
      i = j + 1;
    }
    buffer.write('trailer\n');
    _serialise(buffer, _trailer(_size), 0, 0, encrypt: false);
    buffer.write('\n');
    _out.add(latin1.encode(buffer.toString()));
  }

  /// A cross reference stream, for a file whose own cross reference is one,
  /// since the format does not let a table follow a stream. Uncompressed:
  /// a handful of rows is not worth a filter.
  void _xrefStream(Map<int, int> offsets) {
    final number = _next++;
    final here = _out.length;
    final all = <int, int>{...offsets, number: here};
    final numbers = all.keys.toList()..sort();
    final rows = BytesBuilder(copy: false);
    final index = <Object?>[];
    for (final n in numbers) {
      index
        ..add(n)
        ..add(1);
      final offset = all[n]!;
      final generation = _generations[n] ?? 0;
      rows.add(<int>[
        1,
        (offset >> 24) & 0xff,
        (offset >> 16) & 0xff,
        (offset >> 8) & 0xff,
        offset & 0xff,
        (generation >> 8) & 0xff,
        generation & 0xff,
      ]);
    }
    final data = rows.takeBytes();
    final size = number + 1 > _size ? number + 1 : _size;
    final dict = <String, Object?>{
      'Type': const PdfName('XRef'),
      'W': const <Object?>[1, 4, 2],
      'Index': index,
      'Length': data.length,
      ..._trailer(size),
    };
    final buffer = StringBuffer()..write('$number 0 obj\n');
    _serialise(buffer, dict, number, 0, encrypt: false);
    buffer.write('\nstream\n');
    _out.add(latin1.encode(buffer.toString()));
    _out.add(data);
    _out.add(ascii.encode('\nendstream\nendobj\n'));
  }
}
