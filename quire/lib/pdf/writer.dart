import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:archive/archive.dart';

import 'document.dart';
import 'encodings.dart' show decodePdfText, winAnsiHigh;
import 'interpreter.dart' show userUnitOf;
import 'standard_metrics.dart' show kHelvetica, standardWidths;
import 'lexer.dart' show PdfKeyword, PdfLexer, isWhite;
import 'objects.dart';
import 'truetype.dart';

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

/// Parsed objects put back into the file's own syntax.
///
/// Every writer in this library hands its objects to this one serialiser, so
/// a file quire signs and a file quire seals cannot drift into two dialects of
/// the same format. A name escaped one way here and another way there is the
/// kind of fault that shows up only in somebody else's reader, long after the
/// file has been sent and there is nothing left to compare it against.
class PdfObjectWriter {
  const PdfObjectWriter(this.encryptBytes);

  /// [data] as it has to appear inside the object that holds it: under that
  /// object's own key for a file carrying encryption, handed straight back for
  /// one that is not.
  final Uint8List Function(Uint8List data, int number, int generation)
      encryptBytes;

  /// One whole indirect object, header, body and `endobj`.
  ///
  /// [encrypt] is false for the /Encrypt dictionary alone, whose strings are
  /// what a reader checks a password against and so cannot themselves be
  /// behind the key that password is meant to find.
  Uint8List object(
    int number,
    int generation,
    Object? value, {
    bool encrypt = true,
  }) {
    final buffer = StringBuffer()..write('$number $generation obj\n');
    write(buffer, value, number, generation, encrypt: encrypt);
    buffer.write('\nendobj\n');
    return Uint8List.fromList(latin1.encode(buffer.toString()));
  }

  /// Writes [value]. Strings are encrypted only inside an ordinary object:
  /// the trailer, a cross reference stream and the /Encrypt dictionary are all
  /// read before any key is known, so a string in one of them, the file
  /// identifier above all, has to be written exactly as it is.
  void write(
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
        out.write(real(value));
      case PdfName():
        out.write(name(value.value));
      case PdfRef():
        out.write('${value.number} ${value.generation} R');
      case PdfString():
        // Strings were read in clear, so a string going into an encrypted file
        // goes back in under the key of the object it is now part of, which is
        // what a viewer will decrypt it with.
        final bytes =
            encrypt ? encryptBytes(value.bytes, number, gen) : value.bytes;
        out.write('<');
        for (final b in bytes) {
          out.write(b.toRadixString(16).padLeft(2, '0'));
        }
        out.write('>');
      case List():
        out.write('[');
        for (var i = 0; i < value.length; i++) {
          if (i > 0) out.write(' ');
          write(out, value[i], number, gen, encrypt: encrypt);
        }
        out.write(']');
      case Map<String, Object?>():
        // A key with nothing under it is a key the dictionary does not have.
        // The page tree walk leaves such keys behind for attributes a page did
        // not inherit, and writing them out would only be noise.
        out.write('<<');
        for (final entry in value.entries) {
          if (entry.value == null) continue;
          out
            ..write(' ')
            ..write(name(entry.key))
            ..write(' ');
          write(out, entry.value, number, gen, encrypt: encrypt);
        }
        out.write(' >>');
      case PdfKeyword(value: 'true' || 'false' || 'null'):
        out.write(value.value);
      case PdfStream():
        // A stream belongs to an indirect object of its own and is written by
        // the caller that knows where its bytes go. One turning up nested in a
        // dictionary is a file this writer cannot promise to reproduce.
        throw const PdfWriteError('This page holds data that cannot be copied.');
      default:
        throw const PdfWriteError(
          'This file holds something quire cannot copy into a new version.',
        );
    }
  }

  /// A name with every character the format reserves written as `#xx`.
  static String name(String value) {
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

  /// A number the way the format likes them: no exponent, no trailing zeros,
  /// and a whole value written without its point.
  static String real(double value) {
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

  /// A classic cross reference table over [offsets], up to but not including
  /// the trailer the caller writes after it.
  ///
  /// Both writers arrive here: an update's table covers only the objects it
  /// added, a rewrite's covers the whole file, and either way a row is twenty
  /// bytes wide to the character, because a reader seeks into this table by
  /// arithmetic and cannot be one byte out.
  static String xrefTable(
    Map<int, int> offsets,
    int Function(int number) generationOf,
  ) {
    final numbers = offsets.keys.toList()..sort();
    final buffer = StringBuffer()
      ..writeln('xref')
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
        final n = numbers[k];
        buffer.write(
          '${offsets[n]!.toString().padLeft(10, '0')} '
          '${generationOf(n).toString().padLeft(5, '0')} n \n',
        );
      }
      i = j + 1;
    }
    return buffer.toString();
  }
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
class PdfSignatureWriter extends PdfUpdate {
  PdfSignatureWriter._(super.file);

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

  Uint8List _write(List<PlacedInk> marks) {
    final byPage = <int, List<PlacedInk>>{};
    for (final mark in marks) {
      byPage.putIfAbsent(mark.pageIndex, () => <PlacedInk>[]).add(mark);
    }
    for (final entry in byPage.entries) {
      _signPage(entry.key, entry.value);
    }

    return _finish();
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

    final ink = _inkStream(box, _quarterOf(page), marks, names);
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
    _objects[ref.number] = _writer.object(ref.number, ref.generation, dict);
    _generations[ref.number] = ref.generation;
  }

  /// The content that draws [marks], in the page's user space.
  Uint8List _inkStream(
    List<double> box,
    int quarter,
    List<PlacedInk> marks,
    Map<PlacedInk, String> names,
  ) {
    final x0 = box[0] < box[2] ? box[0] : box[2];
    final y0 = box[1] < box[3] ? box[1] : box[3];
    final width = (box[2] - box[0]).abs();
    final height = (box[3] - box[1]).abs();
    // One matrix carries the whole difference between the two spaces: the
    // reader's, whose origin is the top left of the page as it is read and
    // whose y runs down, and the page's own, whose origin is the bottom left
    // of the box and whose y runs up. Everything after it is written in the
    // reader's coordinates, turn and all.
    final place = switch (quarter) {
      1 => <double>[0, 1, 1, 0, x0, y0],
      2 => <double>[-1, 0, 0, 1, x0 + width, y0],
      3 => <double>[0, -1, -1, 0, x0 + width, y0 + height],
      _ => <double>[1, 0, 0, -1, x0, y0 + height],
    };
    final buffer = StringBuffer()
      ..writeln('Q')
      ..writeln('q');
    for (final value in place) {
      buffer
        ..write(PdfObjectWriter.real(value))
        ..write(' ');
    }
    buffer
      ..writeln('cm')
      ..writeln('0.067 0.067 0.067 rg');
    for (final mark in marks) {
      final name = names[mark];
      if (name != null) {
        // A picture is placed by the matrix that maps the unit square onto
        // the box it was put in: width and height along the diagonal, the
        // bottom left corner in the translation.
        // Height runs the other way in this space, so the picture is
        // placed from the foot of its box with its own axis flipped back.
        buffer
          ..writeln('q')
          ..write(PdfObjectWriter.real(mark.rect.width))
          ..write(' 0 0 ')
          ..write(PdfObjectWriter.real(-mark.rect.height))
          ..write(' ')
          ..write(PdfObjectWriter.real(mark.rect.left))
          ..write(' ')
          ..write(PdfObjectWriter.real(mark.rect.top + mark.rect.height))
          ..writeln(' cm')
          ..writeln('${PdfObjectWriter.name(name)} Do')
          ..writeln('Q');
        continue;
      }
      var drew = false;
      for (final outline in mark.outlines) {
        if (outline.length < 3) continue;
        for (var i = 0; i < outline.length; i++) {
          final point = outline[i];
          final x = mark.rect.left + point.dx * mark.rect.width;
          final y = mark.rect.top + point.dy * mark.rect.height;
          buffer
            ..write(PdfObjectWriter.real(x))
            ..write(' ')
            ..write(PdfObjectWriter.real(y))
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
}

/// What every update quire appends to a PDF shares: new objects numbered
/// after the file's own, pictures written as image objects, the page's box
/// and turn, and a cross reference section of the kind the file already has.
///
/// An update is added after the file's last byte, never written into it. The
/// original is still there, whole, under everything quire added.
abstract class PdfUpdate {
  PdfUpdate(this.file)
      : _next = _firstFreeNumber(file),
        _out = BytesBuilder(copy: false);

  final PdfFile file;
  int _next;
  final BytesBuilder _out;

  /// Objects go out through the file's own key, so an update added to an
  /// encrypted document is encrypted the way the rest of it already is.
  late final PdfObjectWriter _writer = PdfObjectWriter(file.encryptForObject);

  /// New objects by number, each already serialised in full.
  final Map<int, Uint8List> _objects = <int, Uint8List>{};

  /// The generation each new object number carries: 0 for a fresh object,
  /// and the page's own for a page written again.
  final Map<int, int> _generations = <int, int>{};

  static int _firstFreeNumber(PdfFile file) {
    var next = 1;
    for (final number in file.xref.keys) {
      if (number >= next) next = number + 1;
    }
    final size = file.resolve(file.trailer['Size']);
    if (size is int && size > next) next = size;
    return next;
  }

  /// The whole file with every object added so far appended to it.
  Uint8List _finish() {
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

  /// The quarter turns [page] says it is meant to be seen through, which is
  /// the turn the reader drew it with and therefore the turn its coordinates
  /// are in.
  int _quarterOf(Map<String, Object?> page) {
    final raw = file.resolve(page['Rotate']);
    var rot = (raw is num ? raw.toInt() : 0) % 360;
    if (rot < 0) rot += 360;
    return rot % 90 == 0 ? rot ~/ 90 : 0;
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
    final buffer = StringBuffer(
      PdfObjectWriter.xrefTable(offsets, (n) => _generations[n] ?? 0),
    )..write('trailer\n');
    _writer.write(buffer, _trailer(_size), 0, 0, encrypt: false);
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
    _writer.write(buffer, dict, number, 0, encrypt: false);
    buffer.write('\nstream\n');
    _out.add(latin1.encode(buffer.toString()));
    _out.add(data);
    _out.add(ascii.encode('\nendstream\nendobj\n'));
  }
}

/// One change laid onto a page, in the reader's own points: the origin at
/// the top left of the page as it is read, and y running down.
sealed class PageEdit {
  const PageEdit(this.pageIndex);
  final int pageIndex;

  /// The box the mark covers.
  Rect get bounds;

  /// The same mark stretched from [bounds] into [to].
  PageEdit fitted(Rect to);

  /// The same mark put down [by] further on.
  PageEdit moved(Offset by) => fitted(bounds.shift(by));

  /// The same mark on page [page].
  PageEdit onPage(int page);
}

Offset _mapPoint(Offset p, Rect from, Rect to) {
  final sx = from.width == 0 ? 1.0 : to.width / from.width;
  final sy = from.height == 0 ? 1.0 : to.height / from.height;
  return Offset(
    to.left + (p.dx - from.left) * sx,
    to.top + (p.dy - from.top) * sy,
  );
}

Rect _mapRect(Rect r, Rect from, Rect to) => Rect.fromPoints(
      _mapPoint(r.topLeft, from, to),
      _mapPoint(r.bottomRight, from, to),
    );

Rect _span(Iterable<Offset> points) {
  var l = double.infinity, t = double.infinity;
  var r = double.negativeInfinity, b = double.negativeInfinity;
  for (final p in points) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  if (l > r) return Rect.zero;
  return Rect.fromLTRB(l, t, r, b);
}

/// How far in from each side of a box its words start, in points.
class BoxInsets {
  const BoxInsets(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;

  static const BoxInsets zero = BoxInsets(0, 0, 0, 0);

  bool get isZero => left == 0 && top == 0 && right == 0 && bottom == 0;

  BoxInsets scaled(double sx, double sy) =>
      BoxInsets(left * sx, top * sy, right * sx, bottom * sy);

  Rect inside(Rect box) => Rect.fromLTRB(
        box.left + left,
        box.top + top,
        math.max(box.left + left, box.right - right),
        math.max(box.top + top, box.bottom - bottom),
      );
}

/// Words typed onto the page, in a box.
class TextBoxEdit extends PageEdit {
  const TextBoxEdit(
    super.pageIndex, {
    required this.rect,
    required this.text,
    this.size = 12,
    this.color = 0xFF111111,
    this.inset = BoxInsets.zero,
    this.drawn,
    this.family,
  });
  final Rect rect;
  final String text;
  final double size;
  final int color;

  /// The standard PDF typeface another program set the words in, such as
  /// Courier or Times-Roman, which a rewrite keeps; null for the app's own.
  final String? family;

  /// Where in [rect] the words go, for a box another program drew with a
  /// border, a callout or room of its own around them.
  final BoxInsets inset;

  /// The words as the editor drew them, for letters no font here can set.
  /// Only a save fills it in, and any change to the box drops it.
  final PdfImage? drawn;

  /// The box the words are set in.
  Rect get wordsBox => inset.inside(rect);

  @override
  Rect get bounds => rect;

  @override
  TextBoxEdit fitted(Rect to) => copyWith(
        rect: to,
        inset: inset.scaled(
          rect.width == 0 ? 1 : to.width / rect.width,
          rect.height == 0 ? 1 : to.height / rect.height,
        ),
      );

  @override
  TextBoxEdit moved(Offset by) => copyWith(rect: rect.shift(by));

  @override
  TextBoxEdit onPage(int page) => TextBoxEdit(
        page,
        rect: rect,
        text: text,
        size: size,
        color: color,
        inset: inset,
        family: family,
      );

  TextBoxEdit copyWith({
    Rect? rect,
    String? text,
    double? size,
    int? color,
    BoxInsets? inset,
    PdfImage? drawn,
  }) =>
      TextBoxEdit(
        pageIndex,
        rect: rect ?? this.rect,
        text: text ?? this.text,
        size: size ?? this.size,
        color: color ?? this.color,
        inset: inset ?? this.inset,
        drawn: drawn,
        family: family,
      );
}

/// A picture laid onto the page.
class ImageEdit extends PageEdit {
  const ImageEdit(super.pageIndex, {required this.rect, required this.image});
  final Rect rect;
  final PdfImage image;

  @override
  Rect get bounds => rect;

  @override
  ImageEdit fitted(Rect to) => ImageEdit(pageIndex, rect: to, image: image);

  @override
  ImageEdit moved(Offset by) => fitted(bounds.shift(by));

  @override
  ImageEdit onPage(int page) => ImageEdit(page, rect: rect, image: image);
}

/// Lines drawn by hand.
class InkEdit extends PageEdit {
  const InkEdit(
    super.pageIndex, {
    required this.strokes,
    this.width = 2,
    this.color = 0xFF1F4FD8,
    this.opacity = 1,
  });
  final List<List<Offset>> strokes;
  final double width;
  final int color;

  /// How much of what is under the lines shows through them: 1 for none.
  final double opacity;

  @override
  Rect get bounds => _span([for (final s in strokes) ...s]);

  @override
  InkEdit fitted(Rect to) {
    final from = bounds;
    return copyWith(strokes: [
      for (final s in strokes) [for (final p in s) _mapPoint(p, from, to)],
    ]);
  }

  @override
  InkEdit moved(Offset by) => fitted(bounds.shift(by));

  @override
  InkEdit onPage(int page) =>
      InkEdit(page, strokes: strokes, width: width, color: color, opacity: opacity);

  InkEdit copyWith({List<List<Offset>>? strokes, double? width, int? color, double? opacity}) =>
      InkEdit(
        pageIndex,
        strokes: strokes ?? this.strokes,
        width: width ?? this.width,
        color: color ?? this.color,
        opacity: opacity ?? this.opacity,
      );
}

/// Words marked over, one box per line of them, multiplied onto the page so
/// the words stay dark.
class HighlightEdit extends PageEdit {
  const HighlightEdit(super.pageIndex, {required this.rects, this.color = 0xFFFFD84D, this.opacity = 1});
  final List<Rect> rects;
  final int color;
  final double opacity;

  @override
  Rect get bounds => _span([for (final r in rects) ...[r.topLeft, r.bottomRight]]);

  @override
  HighlightEdit fitted(Rect to) {
    final from = bounds;
    return HighlightEdit(
      pageIndex,
      rects: [for (final r in rects) _mapRect(r, from, to)],
      color: color,
      opacity: opacity,
    );
  }

  @override
  HighlightEdit moved(Offset by) => fitted(bounds.shift(by));

  @override
  HighlightEdit onPage(int page) => HighlightEdit(page, rects: rects, color: color, opacity: opacity);

  HighlightEdit copyWith({int? color, double? opacity}) =>
      HighlightEdit(pageIndex, rects: rects, color: color ?? this.color, opacity: opacity ?? this.opacity);
}

/// Words struck through, one box per line of them.
class StrikeEdit extends PageEdit {
  const StrikeEdit(super.pageIndex, {required this.rects, this.color = 0xFFD23B3B, this.opacity = 1});
  final List<Rect> rects;
  final int color;
  final double opacity;

  @override
  Rect get bounds => _span([for (final r in rects) ...[r.topLeft, r.bottomRight]]);

  @override
  StrikeEdit fitted(Rect to) {
    final from = bounds;
    return StrikeEdit(
      pageIndex,
      rects: [for (final r in rects) _mapRect(r, from, to)],
      color: color,
      opacity: opacity,
    );
  }

  @override
  StrikeEdit moved(Offset by) => fitted(bounds.shift(by));

  @override
  StrikeEdit onPage(int page) => StrikeEdit(page, rects: rects, color: color, opacity: opacity);

  StrikeEdit copyWith({int? color, double? opacity}) =>
      StrikeEdit(pageIndex, rects: rects, color: color ?? this.color, opacity: opacity ?? this.opacity);
}

/// A mark already in the file that quire cannot draw again from scratch, a
/// stamp or a box another program made, kept with its own appearance and
/// fitted to [rect]. Added as new, it is a copy of the annotation at
/// [origin].
class KeptEdit extends PageEdit {
  const KeptEdit(super.pageIndex, {required this.rect, this.origin});
  final Rect rect;
  final MarkOrigin? origin;

  @override
  Rect get bounds => rect;

  @override
  KeptEdit fitted(Rect to) => KeptEdit(pageIndex, rect: to, origin: origin);

  @override
  KeptEdit moved(Offset by) => fitted(bounds.shift(by));

  @override
  KeptEdit onPage(int page) => KeptEdit(page, rect: rect, origin: origin);
}

/// Where an annotation already in a file is: its page, and its place in that
/// page's /Annots as the file stands.
class MarkOrigin {
  const MarkOrigin(this.page, this.index);
  final int page;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is MarkOrigin && other.page == page && other.index == index;

  @override
  int get hashCode => Object.hash(page, index);

  @override
  String toString() => 'MarkOrigin($page, $index)';
}

/// What happens to one annotation already in the file.
sealed class MarkUpdate {
  const MarkUpdate(this.origin);
  final MarkOrigin origin;
}

/// Moved [by], in the reader's points, keeping its own appearance.
class MarkMoved extends MarkUpdate {
  const MarkMoved(super.origin, this.by);
  final Offset by;
}

/// Stretched into [rect], keeping its own appearance.
class MarkRefitted extends MarkUpdate {
  const MarkRefitted(super.origin, this.rect);
  final Rect rect;
}

/// Written again from [edit], keeping who made it and what it answers.
class MarkRewritten extends MarkUpdate {
  const MarkRewritten(super.origin, this.edit);
  final PageEdit edit;
}

/// Taken off the page, with the note window it opens.
class MarkRemoved extends MarkUpdate {
  const MarkRemoved(super.origin);
}

/// How a page's reader points map onto its user space, which has its origin
/// at the bottom left and its y running up, turned by the page's /Rotate and
/// scaled by its /UserUnit.
class PagePlace {
  PagePlace(this.m, [this.unit = 1]);

  factory PagePlace.of(PdfFile file, Map<String, Object?> page) {
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
    final raw = file.resolve(page['Rotate']);
    var rot = (raw is num ? raw.toInt() : 0) % 360;
    if (rot < 0) rot += 360;
    final quarter = rot % 90 == 0 ? rot ~/ 90 : 0;
    final x0 = box[0] < box[2] ? box[0] : box[2];
    final y0 = box[1] < box[3] ? box[1] : box[3];
    final width = (box[2] - box[0]).abs();
    final height = (box[3] - box[1]).abs();
    final m = switch (quarter) {
      1 => <double>[0, 1, 1, 0, x0, y0],
      2 => <double>[-1, 0, 0, 1, x0 + width, y0],
      3 => <double>[0, -1, -1, 0, x0 + width, y0 + height],
      _ => <double>[1, 0, 0, -1, x0, y0 + height],
    };
    final unit = userUnitOf(file, page);
    if (unit != 1) {
      for (var i = 0; i < 4; i++) {
        m[i] /= unit;
      }
    }
    return PagePlace(m, unit);
  }

  /// The matrix from the reader's points to user space, as `a b c d e f`.
  final List<double> m;

  /// How many of the reader's points one unit of user space is: the page's
  /// /UserUnit, which sizes stated in user space, a font size in /DA or a
  /// line width in /BS, are scaled by.
  final double unit;

  (double, double) user(Offset p) =>
      (m[0] * p.dx + m[2] * p.dy + m[4], m[1] * p.dx + m[3] * p.dy + m[5]);

  /// How far a step of [d] in the reader's points goes in user space.
  (double, double) userVector(Offset d) =>
      (m[0] * d.dx + m[2] * d.dy, m[1] * d.dx + m[3] * d.dy);

  /// The reader's point at user space ([x], [y]).
  Offset reader(double x, double y) {
    final det = m[0] * m[3] - m[1] * m[2];
    if (det == 0) return Offset.zero;
    final dx = x - m[4], dy = y - m[5];
    return Offset(
      (m[3] * dx - m[2] * dy) / det,
      (-m[1] * dx + m[0] * dy) / det,
    );
  }

  /// The user space box around [points], as `left bottom right top`.
  List<double> userRect(Iterable<Offset> points) {
    var left = double.infinity, bottom = double.infinity;
    var right = double.negativeInfinity, top = double.negativeInfinity;
    for (final p in points) {
      final (x, y) = user(p);
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < bottom) bottom = y;
      if (y > top) top = y;
    }
    return <double>[left, bottom, right, top];
  }

  /// The reader's box around the user space box [r].
  Rect readerRect(List<double> r) => _span([
        reader(r[0], r[1]),
        reader(r[2], r[1]),
        reader(r[0], r[3]),
        reader(r[2], r[3]),
      ]);
}

/// How a box of words is written into a file.
enum WordsFace {
  /// Helvetica, which every reader has, for words it can set.
  standard,

  /// The app's own typeface, put into the file, for letters Helvetica has
  /// not got.
  embedded,

  /// A picture of the words as the editor drew them, for scripts that need
  /// shaping or a typeface the app does not carry.
  drawn,
}

/// [from] and every annotation of [annots] that goes with them: the replies
/// and review states that answer them, at every depth, the members of
/// their groups, and the note windows of all of these.
Set<int> annotationThread(PdfFile file, List<Object?> annots, Set<int> from) {
  final out = <int>{...from};
  var grew = true;
  while (grew) {
    grew = false;
    final numbers = <int>{
      for (final j in out)
        if (annots[j] case final PdfRef ref) ref.number,
    };
    final popups = <int>{
      for (final j in out)
        if (file.dict(annots[j])?['Popup'] case final PdfRef ref) ref.number,
    };
    for (var j = 0; j < annots.length; j++) {
      if (out.contains(j)) continue;
      final raw = annots[j];
      final dict = file.dict(raw);
      if (dict == null) continue;
      final subtype = file.resolve(dict['Subtype']);
      final popup = subtype is PdfName && subtype.value == 'Popup';
      final irt = dict['IRT'], parent = dict['Parent'];
      if ((irt is PdfRef && numbers.contains(irt.number)) ||
          (popup && parent is PdfRef && numbers.contains(parent.number)) ||
          (raw is PdfRef && popups.contains(raw.number))) {
        out.add(j);
        grew = true;
      }
    }
  }
  return out;
}

/// [content] with every text object taken out, which is the drawing of a
/// box of words with its words gone: its border, fill and callout stay. A
/// picture of words quire drew there is taken out too.
Uint8List contentWithoutText(Uint8List content) {
  final lx = PdfLexer(content);
  final cuts = <(int, int)>[];
  int? text;
  (String, int)? name;
  while (true) {
    lx.skipWhitespace();
    if (lx.atEnd) break;
    final at = lx.pos;
    final Object? token;
    try {
      token = lx.parseObject();
    } on Object {
      break;
    }
    if (lx.pos <= at) lx.pos = at + 1;
    if (token is PdfName) {
      name = (token.value, at);
      continue;
    }
    if (token is! PdfKeyword) {
      name = null;
      continue;
    }
    switch (token.value) {
      case 'BT':
        text ??= at;
      case 'ET':
        final start = text;
        if (start != null) {
          cuts.add((start, lx.pos));
          text = null;
        }
      case 'Do':
        final shown = name;
        if (shown != null && shown.$1 == kDrawnWords && text == null) cuts.add((shown.$2, lx.pos));
      case 'BI':
        // An inline image's data is bytes, not operators.
        while (!lx.atEnd) {
          final key = lx.parseObject();
          if (key is PdfKeyword && key.value == 'ID') break;
        }
        var p = lx.pos;
        while (p + 1 < content.length &&
            !(content[p] == 0x45 &&
                content[p + 1] == 0x49 &&
                isWhite(content[p - 1]) &&
                (p + 2 >= content.length || isWhite(content[p + 2])))) {
          p++;
        }
        lx.pos = math.min(p + 2, content.length);
    }
    name = null;
  }
  if (text != null) cuts.add((text, content.length));
  final keep = BytesBuilder(copy: false);
  var from = 0;
  for (final (start, end) in cuts) {
    if (start > from) keep.add(Uint8List.sublistView(content, from, start));
    from = math.max(from, end);
  }
  if (from < content.length) keep.add(Uint8List.sublistView(content, from));
  return keep.takeBytes();
}

/// The name a picture of words is drawn under in an appearance.
const String kDrawnWords = 'QuireDrawn';

/// [text] with the line breaks a PDF text string may hold, CR LF and a
/// lone CR as Acrobat stores Enter, all made LF.
String lineBreaks(String text) => text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Lays [PageEdit]s onto a PDF as annotations, and moves, stretches,
/// rewrites and removes the ones already there, in an update appended to it.
///
/// Every edit is a proper annotation of its own kind, a text box, a stamp, ink,
/// a highlight or a strike out, so another reader lists it as one and can
/// remove it, and each carries an appearance of its own, so every reader
/// draws it the way quire does rather than guessing at it. Nothing already in
/// the file is changed but the annotations asked about and the list of
/// annotations on their pages.
class PdfAnnotator extends PdfUpdate {
  PdfAnnotator._(super.file, this._font);

  /// The whole file with [edits] laid onto its pages.
  static Uint8List annotated(PdfFile file, List<PageEdit> edits, {TrueTypeFont? font}) =>
      apply(file, added: edits, font: font);

  /// The whole file with [added] laid onto its pages and [updates] made to
  /// the annotations already there. Words Helvetica cannot set are set in
  /// [font], which goes into the file with only the letters they use.
  static Uint8List apply(
    PdfFile file, {
    List<PageEdit> added = const <PageEdit>[],
    List<MarkUpdate> updates = const <MarkUpdate>[],
    TrueTypeFont? font,
  }) {
    if (added.isEmpty && updates.isEmpty) return file.bytes;
    if (file.recoveredByScan) {
      throw const PdfWriteError(
        'This file is too damaged to add to without rewriting it.',
      );
    }
    if (file.startxref <= 0) {
      throw const PdfWriteError('This file has no cross reference to add to.');
    }
    if (!allowsComments(file)) {
      throw const PdfWriteError('This file does not allow comments to be added or changed.');
    }
    return PdfAnnotator._(file, font)._write(added, updates);
  }

  /// False when the file forbids comments: its security withholds changing
  /// them from whoever opened it without the owner password, or it is
  /// certified to allow no changes, or only forms and signatures.
  static bool allowsComments(PdfFile file) {
    final security = file.security;
    if (security != null && !file.openedAsOwner && security.permissions & 32 == 0) return false;
    final perms = file.dict(file.dict(file.trailer['Root'])?['Perms']);
    final signature = file.dict(perms?['DocMDP']);
    final references = file.resolve(signature?['Reference']);
    if (references is List) {
      for (final raw in references) {
        final reference = file.dict(raw);
        final method = file.resolve(reference?['TransformMethod']);
        if (method is! PdfName || method.value != 'DocMDP') continue;
        final p = file.resolve(file.dict(reference?['TransformParams'])?['P']);
        final level = p is num ? p.toInt() : 2;
        if (level == 1 || level == 2) return false;
      }
    }
    // A signed field that locks the document against every change, or all
    // but filling in forms, which PDF 2.0 writes as P 1 or 2 in its lock and
    // in its FieldMDP transform.
    final form = file.dict(file.dict(file.trailer['Root'])?['AcroForm']);
    final fields = file.resolve(form?['Fields']);
    final seen = <Object?>{};
    bool locks(Object? raw, int depth) {
      final field = file.dict(raw);
      if (field == null || depth > 8 || !seen.add(raw is PdfRef ? raw.number : field)) return false;
      final kids = file.resolve(field['Kids']);
      if (kids is List && kids.any((k) => locks(k, depth + 1))) return true;
      final type = file.resolve(field['FT']);
      final value = file.dict(field['V']);
      if (type is! PdfName || type.value != 'Sig' || value == null) return false;
      bool tight(Object? p) {
        final level = file.resolve(p);
        return level is num && (level.toInt() == 1 || level.toInt() == 2);
      }

      if (tight(file.dict(field['Lock'])?['P'])) return true;
      final references = file.resolve(value['Reference']);
      if (references is List) {
        for (final r in references) {
          final reference = file.dict(r);
          final method = file.resolve(reference?['TransformMethod']);
          if (method is PdfName && method.value == 'FieldMDP' && tight(file.dict(reference?['TransformParams'])?['P'])) {
            return true;
          }
        }
      }
      return false;
    }

    if (fields is List && fields.any((f) => locks(f, 0))) return false;
    return true;
  }

  final TrueTypeFont? _font;

  /// The object the embedded typeface is written to, once some words need
  /// it, and the letter each of its glyphs was used for.
  int? _fontNumber;
  final Map<int, int> _fontText = <int, int>{};

  int _named = 0;

  Uint8List _write(List<PageEdit> added, List<MarkUpdate> updates) {
    final pages = <int>{
      for (final e in added) e.pageIndex,
      for (final u in updates) u.origin.page,
    }.toList()
      ..sort();
    for (final page in pages) {
      _editPage(
        page,
        [for (final e in added) if (e.pageIndex == page) e],
        [for (final u in updates) if (u.origin.page == page) u],
      );
    }
    _writeFont();
    return _finish();
  }

  void _editPage(int index, List<PageEdit> added, List<MarkUpdate> updates) {
    final pages = file.pages;
    if (index < 0 || index >= pages.length) {
      throw PdfWriteError('Page ${index + 1} is not in this file.');
    }
    final ref = file.pageRefs[index];
    if (ref == null) {
      throw const PdfWriteError('This page cannot be found in the file.');
    }
    final page = pages[index];
    final place = PagePlace.of(file, page);
    final annots = <Object?>[];
    final had = file.resolve(page['Annots']);
    if (had is List) annots.addAll(had);
    var listChanged = added.isNotEmpty;
    final removed = <int>{};
    for (final update in updates) {
      final at = update.origin.index;
      if (at < 0 || at >= annots.length || file.dict(annots[at]) == null) {
        throw PdfWriteError(
          'A mark on page ${index + 1} is no longer in the file.',
        );
      }
      switch (update) {
        case MarkRemoved():
          removed.add(at);
          listChanged = true;
        case MarkMoved():
          listChanged |= _replace(annots, at, _movedDict(annots[at], update.by, place));
        case MarkRefitted():
          final dict = _refitted(file.dict(annots[at])!, place.userRect([update.rect.topLeft, update.rect.bottomRight]))
            ..['M'] = _now();
          listChanged |= _replace(annots, at, dict);
        case MarkRewritten():
          listChanged |= _replace(annots, at, _rewrittenDict(annots[at], update.edit, ref, place));
      }
    }
    final remove = removed.isEmpty ? const <int>{} : annotationThread(file, annots, removed);
    for (final edit in added) {
      annots.add(PdfRef(_annotation(edit, ref, place), 0));
    }
    if (!listChanged) return;
    final kept = <Object?>[
      for (var j = 0; j < annots.length; j++)
        if (!remove.contains(j)) annots[j],
    ];
    final dict = Map<String, Object?>.of(page)..['Annots'] = kept;
    _objects[ref.number] = _writer.object(ref.number, ref.generation, dict);
    _generations[ref.number] = ref.generation;
  }

  /// Puts [dict] where the annotation at [at] was: into its own object when
  /// it has one, which leaves the page's list as it is, or into the list
  /// itself for one written inline, which returns true because the list
  /// changed.
  bool _replace(List<Object?> annots, int at, Map<String, Object?> dict) {
    final raw = annots[at];
    if (raw is PdfRef) {
      _objects[raw.number] = _writer.object(raw.number, raw.generation, dict);
      _generations[raw.number] = raw.generation;
      return false;
    }
    annots[at] = dict;
    return true;
  }

  /// [old] fitted to the box [to], `left bottom right top` in user space:
  /// its points, line, vertices, callout and ink carried from the old box
  /// to the new one the way a reader stretches its appearance, and its
  /// inner box scaled with them, so what it says it is matches what it
  /// draws.
  Map<String, Object?> _refitted(Map<String, Object?> old, List<double> to) {
    final dict = Map<String, Object?>.of(old)..['Rect'] = to;
    final had = _numbers(old['Rect']);
    if (had == null || had.length != 4) return dict..remove('RD');
    final x0 = math.min(had[0], had[2]), y0 = math.min(had[1], had[3]);
    final x1 = math.max(had[0], had[2]), y1 = math.max(had[1], had[3]);
    final sx = x1 == x0 ? 1.0 : (to[2] - to[0]) / (x1 - x0);
    final sy = y1 == y0 ? 1.0 : (to[3] - to[1]) / (y1 - y0);
    List<Object?> carried(List<double> values) => <Object?>[
          for (var i = 0; i < values.length; i++)
            i.isEven ? to[0] + (values[i] - x0) * sx : to[1] + (values[i] - y0) * sy,
        ];
    for (final key in const <String>['QuadPoints', 'CL', 'Vertices', 'L']) {
      final values = _numbers(old[key]);
      if (values != null) dict[key] = carried(values);
    }
    final ink = file.resolve(old['InkList']);
    if (ink is List) {
      dict['InkList'] = <Object?>[for (final stroke in ink) carried(_numbers(stroke) ?? const <double>[])];
    }
    final inner = _numbers(old['RD']);
    if (inner != null && inner.length == 4) {
      dict['RD'] = <Object?>[inner[0] * sx, inner[1] * sy, inner[2] * sx, inner[3] * sy];
    }
    return dict;
  }

  List<double>? _numbers(Object? raw) {
    final list = file.resolve(raw);
    if (list is! List) return null;
    return <double>[
      for (final value in list)
        switch (file.resolve(value)) {
          final num n => n.toDouble(),
          _ => 0.0,
        },
    ];
  }

  Map<String, Object?> _movedDict(Object? raw, Offset by, PagePlace place) {
    final (dx, dy) = place.userVector(by);
    List<Object?> shifted(Object? value) {
      final list = _numbers(value);
      if (list == null) return const <Object?>[];
      return <Object?>[
        for (var i = 0; i < list.length; i++) list[i] + (i.isEven ? dx : dy),
      ];
    }

    final dict = Map<String, Object?>.of(file.dict(raw)!);
    dict['Rect'] = shifted(dict['Rect']);
    for (final key in const <String>['QuadPoints', 'CL', 'Vertices', 'L']) {
      if (dict.containsKey(key)) dict[key] = shifted(dict[key]);
    }
    final ink = file.resolve(dict['InkList']);
    if (ink is List) {
      dict['InkList'] = <Object?>[for (final stroke in ink) shifted(stroke)];
    }
    dict['M'] = _now();
    return dict;
  }

  /// The annotation at [raw] drawn again from [edit]: the new appearance and
  /// the keys that describe it replace the old ones, and who made it, what it
  /// answers and its note window stay.
  Map<String, Object?> _rewrittenDict(
    Object? raw,
    PageEdit edit,
    PdfRef page,
    PagePlace place,
  ) {
    final old = file.dict(raw)!;
    if (edit is KeptEdit) {
      return _refitted(old, place.userRect([edit.rect.topLeft, edit.rect.bottomRight]))..['M'] = _now();
    }
    final subtype = file.resolve(old['Subtype']);
    if (edit is TextBoxEdit && subtype is PdfName && subtype.value == 'FreeText') {
      return _reworded(old, edit, page, place);
    }
    final dict = Map<String, Object?>.of(old);
    // What the new appearance says differently. The line's style and the
    // opacity are kept and set from the edit, not dropped.
    for (final key in const <String>['InkList', 'QuadPoints', 'AS', 'C', 'CA']) {
      dict.remove(key);
    }
    final style = file.dict(old['BS']);
    dict
      ..addAll(_body(edit, place, dash: _dashOf(style)))
      ..['P'] = page
      ..['M'] = _now();
    if (style != null && edit is InkEdit) {
      dict['BS'] = Map<String, Object?>.of(style)..['W'] = edit.width / place.unit;
    }
    return dict;
  }

  /// The dash pattern a border style names, or null for a solid line.
  List<double>? _dashOf(Map<String, Object?>? style) {
    final kind = file.resolve(style?['S']);
    if (kind is! PdfName || kind.value != 'D') return null;
    return _numbers(style?['D']) ?? const <double>[3];
  }

  /// A box of words another program made, or quire made before, with new
  /// words, colour, size or box. Its border, fill, callout and inner box
  /// stay as they were, drawn from its own appearance with only the words
  /// taken out, and the new words go where the old ones were.
  Map<String, Object?> _reworded(
    Map<String, Object?> old,
    TextBoxEdit edit,
    PdfRef page,
    PagePlace place,
  ) {
    final dict = Map<String, Object?>.of(old);
    final to = place.userRect([edit.rect.topLeft, edit.rect.bottomRight]);
    final had = _numbers(old['Rect']);
    if (had != null && had.length == 4) {
      final from = <double>[
        math.min(had[0], had[2]),
        math.min(had[1], had[3]),
        math.max(had[0], had[2]),
        math.max(had[1], had[3]),
      ];
      final sx = from[2] == from[0] ? 1.0 : (to[2] - to[0]) / (from[2] - from[0]);
      final sy = from[3] == from[1] ? 1.0 : (to[3] - to[1]) / (from[3] - from[1]);
      final callout = _numbers(old['CL']);
      if (callout != null) {
        dict['CL'] = <Object?>[
          for (var i = 0; i < callout.length; i++)
            i.isEven ? to[0] + (callout[i] - from[0]) * sx : to[1] + (callout[i] - from[1]) * sy,
        ];
      }
      final inner = _numbers(old['RD']);
      if (inner != null && inner.length == 4) {
        dict['RD'] = <Object?>[inner[0] * sx, inner[1] * sy, inner[2] * sx, inner[3] * sy];
      }
    }
    dict['Rect'] = to;
    final contents = file.resolve(old['Contents']);
    if (contents is! PdfString || lineBreaks(decodePdfText(contents.bytes)) != edit.text) {
      dict['Contents'] = _utf16(edit.text);
    }
    final da = file.resolve(old['DA']);
    dict['DA'] = PdfString(latin1.encode(_restyledDa(
      da is PdfString ? latin1.decode(da.bytes, allowInvalid: true) : '',
      edit.size / place.unit,
      edit.color,
    )));
    final ds = file.resolve(old['DS']);
    if (ds is PdfString) {
      dict['DS'] = _textString(_restyledDs(decodePdfText(ds.bytes), edit.size / place.unit, edit.color));
    }
    // Rich text a program prefers over the words would bring the old ones
    // back.
    dict.remove('RC');
    final look = _normalAppearance(old);
    if (look != null) {
      dict['AP'] = <String, Object?>{'N': PdfRef(_rewordedLook(look, edit, place, to), 0)};
      dict.remove('AS');
    }
    dict
      ..['P'] = page
      ..['M'] = _now();
    return dict;
  }

  /// A copy of a mark the file already holds, as a new annotation where
  /// [edit] puts it: the same dictionary, its points carried to the new
  /// place, and an appearance that draws the original's as the editor
  /// showed it, upright on a page turned another way.
  Map<String, Object?> _copied(KeptEdit edit, PagePlace place) {
    final origin = edit.origin;
    final source = origin == null ? null : file.pages[origin.page];
    final list = source == null ? null : file.resolve(source['Annots']);
    final old = list is List && origin!.index < list.length ? file.dict(list[origin.index]) : null;
    final rect = old == null ? null : _numbers(old['Rect']);
    if (old == null || rect == null || rect.length != 4) {
      throw const PdfWriteError('The mark being copied is no longer in the file.');
    }
    final from = PagePlace.of(file, source!);
    final bounds = from.readerRect(rect);
    final to = edit.rect;
    final sx = bounds.width == 0 ? 1.0 : to.width / bounds.width;
    final sy = bounds.height == 0 ? 1.0 : to.height / bounds.height;
    // The source's user space, to the reader's points on its page, onto the
    // new box, and into the user space of the page it lands on.
    final carry = _mul(
      _mul(_invert(from.m), <double>[sx, 0, 0, sy, to.left - bounds.left * sx, to.top - bounds.top * sy]),
      place.m,
    );
    List<Object?> carried(List<double> values) => <Object?>[
          for (var i = 0; i + 1 < values.length; i += 2) ...<Object?>[
            values[i] * carry[0] + values[i + 1] * carry[2] + carry[4],
            values[i] * carry[1] + values[i + 1] * carry[3] + carry[5],
          ],
        ];
    final body = Map<String, Object?>.of(old);
    for (final key in const <String>['Popup', 'IRT', 'RT', 'StructParent', 'NM', 'Type', 'RD', 'P', 'AP', 'AS']) {
      body.remove(key);
    }
    // The inner box a callout's words sit in, scaled with the copy. A copy
    // turned onto a page the other way round swaps its sides.
    final inner = _numbers(old['RD']);
    if (inner != null && inner.length == 4) {
      if (carry[1].abs() < 1e-9 && carry[2].abs() < 1e-9) {
        final ax = carry[0].abs(), ay = carry[3].abs();
        body['RD'] = <Object?>[inner[0] * ax, inner[1] * ay, inner[2] * ax, inner[3] * ay];
      } else if (carry[0].abs() < 1e-9 && carry[3].abs() < 1e-9) {
        final ax = carry[1].abs(), ay = carry[2].abs();
        body['RD'] = <Object?>[inner[3] * ay, inner[0] * ax, inner[1] * ay, inner[2] * ax];
      }
    }
    final box = place.userRect([to.topLeft, to.bottomRight]);
    body['Rect'] = box;
    for (final key in const <String>['QuadPoints', 'CL', 'Vertices', 'L']) {
      final values = _numbers(old[key]);
      if (values != null) body[key] = carried(values);
    }
    final ink = file.resolve(old['InkList']);
    if (ink is List) {
      body['InkList'] = <Object?>[
        for (final stroke in ink) carried(_numbers(stroke) ?? const <double>[]),
      ];
    }
    final (ref, look) = _normalAppearanceOf(old);
    if (ref != null && look != null) {
      final bbox = _numbers(look.dict['BBox']) ?? rect;
      final matrix = _numbers(look.dict['Matrix']) ?? const <double>[1, 0, 0, 1, 0, 0];
      final fit = _fitOf(bbox, matrix, <double>[
        math.min(rect[0], rect[2]),
        math.min(rect[1], rect[3]),
        math.max(rect[0], rect[2]),
        math.max(rect[1], rect[3]),
      ]);
      final cm = _mul(fit, carry);
      final number = _form(
        box,
        <String, Object?>{
          'XObject': <String, Object?>{'Kept': ref},
        },
        ascii.encode('q ${cm.map(_r).join(' ')} cm /Kept Do Q\n'),
      );
      body['AP'] = <String, Object?>{'N': PdfRef(number, 0)};
    }
    return body;
  }

  /// The matrix a reader stretches an appearance with: its box, turned by
  /// its matrix, onto the annotation's [rect].
  static List<double> _fitOf(List<double> bbox, List<double> matrix, List<double> rect) {
    final corners = <(double, double)>[
      for (final (x, y) in [(bbox[0], bbox[1]), (bbox[2], bbox[1]), (bbox[0], bbox[3]), (bbox[2], bbox[3])])
        (matrix[0] * x + matrix[2] * y + matrix[4], matrix[1] * x + matrix[3] * y + matrix[5]),
    ];
    final x0 = corners.map((c) => c.$1).reduce(math.min), x1 = corners.map((c) => c.$1).reduce(math.max);
    final y0 = corners.map((c) => c.$2).reduce(math.min), y1 = corners.map((c) => c.$2).reduce(math.max);
    final sx = x1 == x0 ? 1.0 : (rect[2] - rect[0]) / (x1 - x0);
    final sy = y1 == y0 ? 1.0 : (rect[3] - rect[1]) / (y1 - y0);
    return <double>[sx, 0, 0, sy, rect[0] - x0 * sx, rect[1] - y0 * sy];
  }

  /// The normal appearance of [annot], and the reference it is held under.
  (PdfRef?, PdfStream?) _normalAppearanceOf(Map<String, Object?> annot) {
    var raw = file.dict(annot['AP'])?['N'];
    final normal = file.resolve(raw);
    if (normal is Map<String, Object?>) {
      final state = file.resolve(annot['AS']);
      raw = state is PdfName ? normal[state.value] : null;
    }
    final look = file.resolve(raw);
    return (raw is PdfRef ? raw : null, look is PdfStream ? look : null);
  }

  PdfStream? _normalAppearance(Map<String, Object?> annot) {
    final normal = file.resolve(file.dict(annot['AP'])?['N']);
    if (normal is PdfStream) return normal;
    if (normal is Map<String, Object?>) {
      final state = file.resolve(annot['AS']);
      final chosen = file.resolve(state is PdfName ? normal[state.value] : null);
      if (chosen is PdfStream) return chosen;
    }
    return null;
  }

  /// [look] with its words taken out and [edit]'s written in, fitted to
  /// the annotation's new box [rect] the way a reader fits it.
  int _rewordedLook(PdfStream look, TextBoxEdit edit, PagePlace place, List<double> rect) {
    final bbox = _numbers(look.dict['BBox']) ?? rect;
    final matrix = _numbers(look.dict['Matrix']) ?? const <double>[1, 0, 0, 1, 0, 0];
    final Map<String, Object?> resources;
    try {
      resources = _wordless(file.dict(look.dict['Resources']) ?? const <String, Object?>{}, 0);
    } on Object {
      throw const PdfWriteError('This box of words is drawn in a way quire cannot change.');
    }
    final words = _words(edit, resources);
    final fit = _fitOf(bbox, matrix, rect);
    final toForm = _mul(place.m, _invert(_mul(matrix, fit)));
    final Uint8List before;
    try {
      before = contentWithoutText(file.decodeStream(look));
    } on Object {
      throw const PdfWriteError('This box of words is drawn in a way quire cannot change.');
    }
    final content = BytesBuilder(copy: false)
      ..add(ascii.encode('q\n'))
      ..add(before)
      ..add(ascii.encode('\nQ\nq\n${toForm.map(_r).join(' ')} cm\n'))
      ..add(latin1.encode(words))
      ..add(ascii.encode('Q\n'));
    return _form(bbox, resources, content.takeBytes(), matrix: matrix);
  }

  /// [resources] with the words taken out of every form they draw, however
  /// deep, each form written again as a copy of its own so the forms other
  /// marks share are left as they are, and words quire drew as a picture
  /// dropped.
  Map<String, Object?> _wordless(Map<String, Object?> resources, int depth) {
    final out = Map<String, Object?>.of(resources);
    final pictures = file.dict(resources['XObject']);
    if (pictures == null) return out;
    final next = <String, Object?>{};
    for (final entry in pictures.entries) {
      if (entry.key == kDrawnWords) continue;
      final form = file.resolve(entry.value);
      final subtype = form is PdfStream ? file.resolve(form.dict['Subtype']) : null;
      if (form is! PdfStream || subtype is! PdfName || subtype.value != 'Form' || depth > 6) {
        next[entry.key] = entry.value;
        continue;
      }
      final dict = Map<String, Object?>.of(form.dict)
        ..remove('Length')
        ..remove('Filter')
        ..remove('DecodeParms');
      final inner = file.dict(form.dict['Resources']);
      if (inner != null) dict['Resources'] = _wordless(inner, depth + 1);
      final number = _next++;
      _streamObject(number, dict, contentWithoutText(file.decodeStream(form)));
      next[entry.key] = PdfRef(number, 0);
    }
    out['XObject'] = next;
    return out;
  }

  static List<double> _mul(List<double> m, List<double> n) => <double>[
        m[0] * n[0] + m[1] * n[2],
        m[0] * n[1] + m[1] * n[3],
        m[2] * n[0] + m[3] * n[2],
        m[2] * n[1] + m[3] * n[3],
        m[4] * n[0] + m[5] * n[2] + n[4],
        m[4] * n[1] + m[5] * n[3] + n[5],
      ];

  static List<double> _invert(List<double> m) {
    final det = m[0] * m[3] - m[1] * m[2];
    if (det == 0) return const <double>[1, 0, 0, 1, 0, 0];
    final a = m[3] / det, b = -m[1] / det, c = -m[2] / det, d = m[0] / det;
    return <double>[a, b, c, d, -(m[4] * a + m[5] * c), -(m[4] * b + m[5] * d)];
  }

  static final RegExp _number = RegExp(r'[+-]?(?:\d+\.?\d*|\.\d+)');

  /// A default appearance string set to [size] and [argb], keeping the font
  /// it names and anything else it says.
  static String _restyledDa(String da, double size, int argb) {
    final n = _number.pattern;
    var out = da.replaceAllMapped(
      RegExp('(/[^\\s/\\[\\]()<>{}%]+\\s+)$n(\\s+Tf)'),
      (m) => '${m[1]}${_r(size)}${m[2]}',
    );
    if (!out.contains(RegExp(r'Tf(?![A-Za-z])'))) out = '/Helv ${_r(size)} Tf $out';
    out = out
        .replaceAll(RegExp('(?:$n\\s+){3}rg(?![A-Za-z])'), '')
        .replaceAll(RegExp('(?:$n\\s+){4}k(?![A-Za-z])'), '')
        .replaceAll(RegExp('$n\\s+g(?![A-Za-z])'), '');
    return '${out.trim().replaceAll(RegExp(r'\s+'), ' ')} ${_colour(argb)}';
  }

  /// A default style string with its colour and type size set to [argb]
  /// and [size].
  static String _restyledDs(String ds, double size, int argb) {
    final hex = '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    var out = ds.replaceAllMapped(
      RegExp(r'(\d+\.?\d*|\.\d+)pt'),
      (m) => '${_r(size)}pt',
    );
    final colour = RegExp(r'(^|;)\s*color\s*:\s*[^;]*');
    out = colour.hasMatch(out)
        ? out.replaceAllMapped(colour, (m) => '${m[1]}color:$hex')
        : '$out;color:$hex';
    return out;
  }

  /// How tall a box of [text] at [size] and [width] must be for every line
  /// of it to be written.
  static double wordsHeight(String text, double size, double width, {TrueTypeFont? font, String? family}) =>
      (wrapWords(text, size, width, font: font, family: family).length * 1.2 + 0.3) * size;

  PdfString _now() => PdfString(ascii.encode(_pdfDate(DateTime.now().toUtc())));

  static String _r(double v) => PdfObjectWriter.real(v);

  static String _colour(int argb, {bool stroke = false}) {
    final r = ((argb >> 16) & 0xff) / 255;
    final g = ((argb >> 8) & 0xff) / 255;
    final b = (argb & 0xff) / 255;
    return '${_r(r)} ${_r(g)} ${_r(b)} ${stroke ? 'RG' : 'rg'}';
  }

  static List<Object?> _colourArray(int argb) => <Object?>[
        ((argb >> 16) & 0xff) / 255,
        ((argb >> 8) & 0xff) / 255,
        (argb & 0xff) / 255,
      ];

  /// Writes [edit] as a new annotation with its appearance, and returns its
  /// object number.
  int _annotation(PageEdit edit, PdfRef page, PagePlace place) {
    final Map<String, Object?> body;
    if (edit is KeptEdit) {
      body = _copied(edit, place);
    } else {
      body = _body(edit, place);
    }
    final number = _next++;
    final dict = <String, Object?>{
      'Type': const PdfName('Annot'),
      ...body,
      'P': page,
      'F': 4,
      'NM': PdfString(ascii.encode('quire-${DateTime.now().microsecondsSinceEpoch}-${_named++}')),
      'T': PdfString(ascii.encode('quire')),
      'M': _now(),
    };
    _objects[number] = _writer.object(number, 0, dict);
    _generations[number] = 0;
    return number;
  }

  /// Which way [text] is written with [font] to hand. Words another program
  /// set in a standard typeface, [family], stay in it while it can set them.
  static WordsFace wordsFace(String text, TrueTypeFont? font, {String? family}) {
    var plain = true;
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x3F || rune == 0x09) continue;
      if (_winAnsiCode(rune) == 0x3F) {
        plain = false;
        break;
      }
    }
    if (family != null && plain) return WordsFace.standard;
    if (font == null) return plain ? WordsFace.standard : WordsFace.drawn;
    for (final rune in text.runes) {
      if (rune == 0x0A || rune == 0x0D || rune == 0x09) continue;
      if (!font.covers(rune) || font.glyphFor(rune) == 0 || _shaped(rune)) return WordsFace.drawn;
    }
    return WordsFace.embedded;
  }

  /// The name /DA gives the standard typeface [family], as forms name them.
  static String _daName(String? family) => switch (family) {
        'Helvetica-Bold' => 'HeBo',
        'Helvetica-Oblique' => 'HeOb',
        'Helvetica-BoldOblique' => 'HeBO',
        'Times-Roman' => 'TiRo',
        'Times-Bold' => 'TiBo',
        'Times-Italic' => 'TiIt',
        'Times-BoldItalic' => 'TiBI',
        'Courier' => 'Cour',
        'Courier-Bold' => 'CoBo',
        'Courier-Oblique' => 'CoOb',
        'Courier-BoldOblique' => 'CoBO',
        _ => 'Helv',
      };

  /// True for a character that takes its place from the letters around it,
  /// which setting one glyph after another cannot do: marks that sit on a
  /// letter, joiners, variation selectors, and the scripts written right to
  /// left.
  static bool _shaped(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x0483 && rune <= 0x0489) ||
      (rune >= 0x0590 && rune <= 0x08FF) ||
      (rune >= 0x1AB0 && rune <= 0x1AFF) ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x20D0 && rune <= 0x20FF) ||
      (rune >= 0xFB1D && rune <= 0xFDFF) ||
      (rune >= 0xFE00 && rune <= 0xFE0F) ||
      (rune >= 0xFE20 && rune <= 0xFE2F) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);

  /// The drawing of [edit]'s words in the reader's points, its fonts or
  /// picture added to [resources].
  String _words(TextBoxEdit edit, Map<String, Object?> resources) {
    final box = edit.wordsBox;
    final out = StringBuffer();
    final drawn = edit.drawn;
    if (drawn != null) {
      final pictures = Map<String, Object?>.of(file.dict(resources['XObject']) ?? const <String, Object?>{})
        ..[kDrawnWords] = PdfRef(_addImage(drawn), 0);
      resources['XObject'] = pictures;
      out.writeln(
        'q ${_r(box.width)} 0 0 ${_r(-box.height)} ${_r(box.left)} ${_r(box.bottom)} cm /$kDrawnWords Do Q',
      );
      return out.toString();
    }
    final font = _font;
    final face = wordsFace(edit.text, font, family: edit.family);
    final embedded = font != null && face != WordsFace.standard;
    final fonts = Map<String, Object?>.of(file.dict(resources['Font']) ?? const <String, Object?>{});
    if (embedded) {
      fonts['QuireWords'] = PdfRef(_fontNumber ??= _next++, 0);
    } else {
      fonts['QuireHelv'] = <String, Object?>{
        'Type': const PdfName('Font'),
        'Subtype': const PdfName('Type1'),
        'BaseFont': PdfName(edit.family ?? 'Helvetica'),
        'Encoding': const PdfName('WinAnsiEncoding'),
      };
    }
    resources['Font'] = fonts;
    out.writeln(_colour(edit.color));
    // A tab in words is set as a space, as a text box sets it.
    final lines = wrapWords(edit.text.replaceAll('\t', ' '), edit.size, box.width, font: embedded ? font : null, family: edit.family);
    var baseline = box.top + edit.size;
    for (final line in lines) {
      if (baseline > box.bottom + edit.size * 0.3) break;
      final shown = embedded ? _glyphString(font, line) : _winAnsiString(line);
      // The reader's y runs down, so the text matrix flips it back up.
      out.writeln(
        'BT /${embedded ? 'QuireWords' : 'QuireHelv'} ${_r(edit.size)} Tf 1 0 0 -1 '
        '${_r(box.left)} ${_r(baseline)} Tm $shown Tj ET',
      );
      baseline += edit.size * 1.2;
    }
    return out.toString();
  }

  String _glyphString(TrueTypeFont font, String line) {
    final out = StringBuffer('<');
    for (final rune in line.runes) {
      final glyph = font.glyphFor(rune);
      _fontText.putIfAbsent(glyph, () => rune);
      out.write(glyph.toRadixString(16).padLeft(4, '0'));
    }
    out.write('>');
    return out.toString();
  }

  /// The embedded typeface, cut down to the glyphs the words used.
  void _writeFont() {
    final number = _fontNumber;
    final font = _font;
    if (number == null || font == null) return;
    final glyphs = <int>{0, ..._fontText.keys};
    final text = Map<int, int>.of(_fontText)..remove(0);
    var hash = 0;
    for (final g in glyphs.toList()..sort()) {
      hash = (hash * 31 + g) & 0x7FFFFFFF;
    }
    final tag = String.fromCharCodes([for (var i = 0; i < 6; i++) 0x41 + (hash >> (i * 4)) % 26]);
    final name = PdfName('$tag+${font.postScriptName ?? 'Font'}');
    final descendant = _next++, descriptor = _next++, embedded = _next++, map = _next++;
    final scale = 1000 / font.unitsPerEm;
    _objects[number] = _writer.object(number, 0, <String, Object?>{
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('Type0'),
      'BaseFont': name,
      'Encoding': const PdfName('Identity-H'),
      'DescendantFonts': <Object?>[PdfRef(descendant, 0)],
      'ToUnicode': PdfRef(map, 0),
    });
    _generations[number] = 0;
    _objects[descendant] = _writer.object(descendant, 0, <String, Object?>{
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('CIDFontType2'),
      'BaseFont': name,
      'CIDSystemInfo': <String, Object?>{
        'Registry': PdfString(ascii.encode('Adobe')),
        'Ordering': PdfString(ascii.encode('Identity')),
        'Supplement': 0,
      },
      'FontDescriptor': PdfRef(descriptor, 0),
      'DW': 0,
      'W': <Object?>[
        for (final g in glyphs.toList()..sort()) ...<Object?>[g, <Object?>[font.widthOf(g)]],
      ],
      'CIDToGIDMap': const PdfName('Identity'),
    });
    _generations[descendant] = 0;
    _objects[descriptor] = _writer.object(descriptor, 0, <String, Object?>{
      'Type': const PdfName('FontDescriptor'),
      'FontName': name,
      'Flags': 32,
      'FontBBox': <Object?>[for (final v in font.bbox) v * scale],
      'ItalicAngle': 0,
      'Ascent': font.ascender * scale,
      'Descent': font.descender * scale,
      'CapHeight': font.ascender * scale * 0.72,
      'StemV': 80,
      'FontFile2': PdfRef(embedded, 0),
    });
    _generations[descriptor] = 0;
    final subset = font.subset(glyphs);
    _streamObject(embedded, <String, Object?>{
      'Length1': subset.length,
      'Filter': const PdfName('FlateDecode'),
    }, Uint8List.fromList(const ZLibEncoder().encodeBytes(subset)));
    _streamObject(map, const <String, Object?>{}, latin1.encode(pdfToUnicode(text)));
  }

  /// The keys that make [edit] the annotation it is, its rectangle and its
  /// appearance, with the appearance already written.
  Map<String, Object?> _body(PageEdit edit, PagePlace place, {List<double>? dash}) {
    final draw = StringBuffer()
      ..writeln('q')
      ..writeln('${place.m.map(_r).join(' ')} cm');
    final resources = <String, Object?>{};
    void seeThrough(double opacity, {bool multiply = false}) {
      if (opacity >= 1 && !multiply) return;
      resources['ExtGState'] = <String, Object?>{
        'Mark': <String, Object?>{
          'Type': const PdfName('ExtGState'),
          'CA': opacity,
          'ca': opacity,
          if (multiply) 'BM': const PdfName('Multiply'),
        },
      };
      draw.writeln('/Mark gs');
    }

    final Map<String, Object?> annot;
    final List<double> rect;
    switch (edit) {
      case KeptEdit():
        throw const PdfWriteError('A kept mark has no appearance of its own to write.');
      case TextBoxEdit():
        rect = place.userRect([edit.rect.topLeft, edit.rect.bottomRight]);
        draw.write(_words(edit, resources));
        annot = <String, Object?>{
          'Subtype': const PdfName('FreeText'),
          'Contents': _utf16(edit.text),
          'DA': PdfString(latin1.encode('/${_daName(edit.family)} ${_r(edit.size / place.unit)} Tf ${_colour(edit.color)}')),
          'C': <Object?>[],
        };
      case ImageEdit():
        rect = place.userRect([edit.rect.topLeft, edit.rect.bottomRight]);
        resources['XObject'] = <String, Object?>{
          'Img': PdfRef(_addImage(edit.image), 0),
        };
        draw
          ..writeln(
            '${_r(edit.rect.width)} 0 0 ${_r(-edit.rect.height)} '
            '${_r(edit.rect.left)} ${_r(edit.rect.bottom)} cm',
          )
          ..writeln('/Img Do');
        annot = <String, Object?>{
          'Subtype': const PdfName('Stamp'),
          'Name': const PdfName('Image'),
        };
      case InkEdit():
        final points = [for (final s in edit.strokes) ...s];
        if (points.isEmpty) {
          throw const PdfWriteError('A drawing has no lines to write.');
        }
        final pad = edit.width;
        final box = place.userRect(points);
        final reach = pad / place.unit;
        rect = <double>[box[0] - reach, box[1] - reach, box[2] + reach, box[3] + reach];
        seeThrough(edit.opacity);
        draw
          ..writeln(_colour(edit.color, stroke: true))
          ..writeln('${_r(edit.width)} w 1 J 1 j');
        if (dash != null) draw.writeln('[${dash.map((v) => _r(v * place.unit)).join(' ')}] 0 d');
        for (final stroke in edit.strokes) {
          if (stroke.isEmpty) continue;
          for (var i = 0; i < stroke.length; i++) {
            draw.writeln('${_r(stroke[i].dx)} ${_r(stroke[i].dy)} ${i == 0 ? 'm' : 'l'}');
          }
          if (stroke.length == 1) {
            draw.writeln('${_r(stroke[0].dx)} ${_r(stroke[0].dy)} l');
          }
          draw.writeln('S');
        }
        annot = <String, Object?>{
          'Subtype': const PdfName('Ink'),
          'InkList': <Object?>[
            for (final stroke in edit.strokes)
              <Object?>[
                for (final p in stroke) ...() {
                  final (x, y) = place.user(p);
                  return <Object?>[x, y];
                }(),
              ],
          ],
          'BS': <String, Object?>{'W': edit.width / place.unit},
          'C': _colourArray(edit.color),
          if (edit.opacity < 1) 'CA': edit.opacity,
        };
      case HighlightEdit():
        if (edit.rects.isEmpty) {
          throw const PdfWriteError('A highlight covers nothing.');
        }
        rect = place.userRect([
          for (final r in edit.rects) ...[r.topLeft, r.bottomRight],
        ]);
        seeThrough(edit.opacity, multiply: true);
        draw.writeln(_colour(edit.color));
        for (final r in edit.rects) {
          draw.writeln('${_r(r.left)} ${_r(r.top)} ${_r(r.width)} ${_r(r.height)} re f');
        }
        annot = <String, Object?>{
          'Subtype': const PdfName('Highlight'),
          'QuadPoints': _quads(place, edit.rects),
          'C': _colourArray(edit.color),
          if (edit.opacity < 1) 'CA': edit.opacity,
        };
      case StrikeEdit():
        if (edit.rects.isEmpty) {
          throw const PdfWriteError('A strike through covers nothing.');
        }
        rect = place.userRect([
          for (final r in edit.rects) ...[r.topLeft, r.bottomRight],
        ]);
        seeThrough(edit.opacity);
        draw.writeln(_colour(edit.color, stroke: true));
        for (final r in edit.rects) {
          final weight = r.height * 0.08 < 0.8 ? 0.8 : r.height * 0.08;
          final middle = r.top + r.height * 0.55;
          draw
            ..writeln('${_r(weight)} w')
            ..writeln('${_r(r.left)} ${_r(middle)} m ${_r(r.right)} ${_r(middle)} l S');
        }
        annot = <String, Object?>{
          'Subtype': const PdfName('StrikeOut'),
          'QuadPoints': _quads(place, edit.rects),
          'C': _colourArray(edit.color),
          if (edit.opacity < 1) 'CA': edit.opacity,
        };
    }
    draw.writeln('Q');
    final appearance = _form(rect, resources, latin1.encode(draw.toString()));
    return <String, Object?>{
      ...annot,
      'Rect': rect,
      'AP': <String, Object?>{'N': PdfRef(appearance, 0)},
    };
  }

  /// A form XObject drawing [content], its box the annotation's own, so the
  /// appearance lands exactly where it was drawn.
  int _form(
    List<double> bbox,
    Map<String, Object?> resources,
    Uint8List content, {
    List<double>? matrix,
  }) {
    final number = _next++;
    _streamObject(number, <String, Object?>{
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Form'),
      'BBox': bbox,
      'Matrix': ?matrix,
      'Resources': resources,
    }, content);
    return number;
  }

  /// Writes a stream object [number] with [dict] and [data], encrypted the
  /// way the file's own streams are.
  void _streamObject(int number, Map<String, Object?> dict, Uint8List data) {
    final body = file.encryptForObject(data, number, 0);
    final buffer = StringBuffer()..write('$number 0 obj\n');
    _writer.write(
      buffer,
      <String, Object?>{...dict, 'Length': body.length},
      number,
      0,
      encrypt: true,
    );
    buffer.write('\nstream\n');
    _objects[number] = (BytesBuilder(copy: false)
          ..add(latin1.encode(buffer.toString()))
          ..add(body)
          ..add(ascii.encode('\nendstream\nendobj\n')))
        .takeBytes();
    _generations[number] = 0;
  }

  /// Each box as the four corners a text markup names: top left, top right,
  /// bottom left, bottom right, in user space.
  static List<Object?> _quads(PagePlace place, List<Rect> rects) => <Object?>[
        for (final r in rects)
          for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight])
            ...() {
              final (x, y) = place.user(p);
              return <Object?>[x, y];
            }(),
      ];

  /// [text] broken into lines that fit [width] at [size], at the words where
  /// it can and inside a word where one is too long, which is how a box of
  /// words is written and so how an editor must preview it. Measured in
  /// Helvetica, or in [font] when the words are set in it.
  static List<String> wrapWords(String text, double size, double width, {TrueTypeFont? font, String? family}) {
    final face = wordsFace(text, font, family: family);
    final set = font != null && face == WordsFace.embedded ? font : null;
    final widths = (family == null ? null : standardWidths(family.toLowerCase())) ?? kHelvetica;
    double measure(String s) {
      if (set != null) return set.measure(s, size);
      var total = 0.0;
      for (final rune in s.runes) {
        final code = _winAnsiCode(rune);
        total += widths[code < widths.length ? code : 63] * size;
      }
      return total;
    }

    final out = <String>[];
    for (final paragraph in lineBreaks(text).split('\n')) {
      var line = '';
      for (final word in paragraph.split(' ')) {
        final tried = line.isEmpty ? word : '$line $word';
        if (measure(tried) <= width || line.isEmpty && measure(word) <= width) {
          line = tried;
          continue;
        }
        if (line.isNotEmpty) out.add(line);
        line = word;
        while (measure(line) > width && line.length > 1) {
          var cut = line.length - 1;
          while (cut > 1 && measure(line.substring(0, cut)) > width) {
            cut--;
          }
          out.add(line.substring(0, cut));
          line = line.substring(cut);
        }
      }
      out.add(line);
    }
    return out;
  }

  /// The WinAnsi code for [rune], or `?` for one Helvetica's WinAnsi cannot
  /// set, which is the honest answer for a character this font does not have.
  static int _winAnsiCode(int rune) {
    if (rune >= 0x20 && rune < 0x7F) return rune;
    for (final entry in winAnsiHigh.entries) {
      if (entry.value == rune) return entry.key;
    }
    if (rune >= 0xA0 && rune <= 0xFF) return rune;
    return 0x3F;
  }

  static String _winAnsiString(String line) {
    final out = StringBuffer('(');
    for (final rune in line.runes) {
      final code = _winAnsiCode(rune);
      if (code == 0x28 || code == 0x29 || code == 0x5C) {
        out.write('\\${String.fromCharCode(code)}');
      } else if (code < 0x20 || code > 0x7E) {
        out.write('\\${code.toRadixString(8).padLeft(3, '0')}');
      } else {
        out.writeCharCode(code);
      }
    }
    out.write(')');
    return out.toString();
  }

  static PdfString _utf16(String text) {
    final out = <int>[0xFE, 0xFF];
    for (final unit in text.codeUnits) {
      out
        ..add(unit >> 8)
        ..add(unit & 0xff);
    }
    return PdfString(Uint8List.fromList(out));
  }

  /// [text] as a text string: in PDFDocEncoding's Latin-1 half when it fits
  /// there, and in UTF-16 otherwise.
  static PdfString _textString(String text) {
    if (text.codeUnits.every((u) => u < 0x7F && (u >= 0x20 || u == 0x0A || u == 0x0D || u == 0x09))) {
      return PdfString(Uint8List.fromList(text.codeUnits));
    }
    return _utf16(text);
  }

  static String _pdfDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "D:${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}Z";
  }
}
