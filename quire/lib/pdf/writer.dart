import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:archive/archive.dart';

import 'document.dart';
import 'encodings.dart' show winAnsiHigh;
import 'standard_metrics.dart' show kHelvetica;
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
}

/// Words typed onto the page, in a box.
class TextBoxEdit extends PageEdit {
  const TextBoxEdit(
    super.pageIndex, {
    required this.rect,
    required this.text,
    this.size = 12,
    this.color = 0xFF111111,
  });
  final Rect rect;
  final String text;
  final double size;
  final int color;
}

/// A picture laid onto the page.
class ImageEdit extends PageEdit {
  const ImageEdit(super.pageIndex, {required this.rect, required this.image});
  final Rect rect;
  final PdfImage image;
}

/// Lines drawn by hand.
class InkEdit extends PageEdit {
  const InkEdit(
    super.pageIndex, {
    required this.strokes,
    this.width = 2,
    this.color = 0xFF1F4FD8,
  });
  final List<List<Offset>> strokes;
  final double width;
  final int color;
}

/// Words marked over, one box per line of them.
class HighlightEdit extends PageEdit {
  const HighlightEdit(super.pageIndex, {required this.rects, this.color = 0xFFFFD84D});
  final List<Rect> rects;
  final int color;
}

/// Words struck through, one box per line of them.
class StrikeEdit extends PageEdit {
  const StrikeEdit(super.pageIndex, {required this.rects, this.color = 0xFFD23B3B});
  final List<Rect> rects;
  final int color;
}

/// Lays [PageEdit]s onto a PDF as annotations, in an update appended to it.
///
/// Every edit is a proper annotation of its own kind, a text box, a stamp, ink,
/// a highlight or a strike out, so another reader lists it as one and can
/// remove it, and each carries an appearance of its own, so every reader
/// draws it the way quire does rather than guessing at it. Nothing already in
/// the file is changed but the list of annotations on the pages written to.
class PdfAnnotator extends PdfUpdate {
  PdfAnnotator._(super.file);

  /// The whole file with [edits] laid onto its pages.
  static Uint8List annotated(PdfFile file, List<PageEdit> edits) {
    if (edits.isEmpty) return file.bytes;
    if (file.recoveredByScan) {
      throw const PdfWriteError(
        'This file is too damaged to add to without rewriting it.',
      );
    }
    if (file.startxref <= 0) {
      throw const PdfWriteError('This file has no cross reference to add to.');
    }
    return PdfAnnotator._(file)._write(edits);
  }

  int _named = 0;

  Uint8List _write(List<PageEdit> edits) {
    final byPage = <int, List<PageEdit>>{};
    for (final edit in edits) {
      byPage.putIfAbsent(edit.pageIndex, () => <PageEdit>[]).add(edit);
    }
    for (final entry in byPage.entries) {
      _annotatePage(entry.key, entry.value);
    }
    return _finish();
  }

  void _annotatePage(int index, List<PageEdit> edits) {
    final pages = file.pages;
    if (index < 0 || index >= pages.length) {
      throw PdfWriteError('Page ${index + 1} is not in this file.');
    }
    final ref = file.pageRefs[index];
    if (ref == null) {
      throw const PdfWriteError('This page cannot be found in the file.');
    }
    final page = pages[index];
    final place = _placeFor(_boxOf(page), _quarterOf(page));
    final annots = <Object?>[];
    final had = file.resolve(page['Annots']);
    if (had is List) annots.addAll(had);
    for (final edit in edits) {
      annots.add(PdfRef(_annotation(edit, ref, place), 0));
    }
    final dict = Map<String, Object?>.of(page)..['Annots'] = annots;
    _objects[ref.number] = _writer.object(ref.number, ref.generation, dict);
    _generations[ref.number] = ref.generation;
  }

  /// The matrix from the reader's points to the page's user space, as
  /// `a b c d e f`.
  static List<double> _placeFor(List<double> box, int quarter) {
    final x0 = box[0] < box[2] ? box[0] : box[2];
    final y0 = box[1] < box[3] ? box[1] : box[3];
    final width = (box[2] - box[0]).abs();
    final height = (box[3] - box[1]).abs();
    return switch (quarter) {
      1 => <double>[0, 1, 1, 0, x0, y0],
      2 => <double>[-1, 0, 0, 1, x0 + width, y0],
      3 => <double>[0, -1, -1, 0, x0 + width, y0 + height],
      _ => <double>[1, 0, 0, -1, x0, y0 + height],
    };
  }

  static (double, double) _user(List<double> m, Offset p) =>
      (m[0] * p.dx + m[2] * p.dy + m[4], m[1] * p.dx + m[3] * p.dy + m[5]);

  static List<double> _userRect(List<double> m, Iterable<Offset> points) {
    var left = double.infinity, bottom = double.infinity;
    var right = double.negativeInfinity, top = double.negativeInfinity;
    for (final p in points) {
      final (x, y) = _user(m, p);
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < bottom) bottom = y;
      if (y > top) top = y;
    }
    return <double>[left, bottom, right, top];
  }

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

  /// Writes [edit] as an annotation with its appearance, and returns its
  /// object number.
  int _annotation(PageEdit edit, PdfRef page, List<double> place) {
    final draw = StringBuffer()
      ..writeln('q')
      ..writeln('${place.map(_r).join(' ')} cm');
    final resources = <String, Object?>{};
    final Map<String, Object?> annot;
    final List<double> rect;
    switch (edit) {
      case TextBoxEdit():
        rect = _userRect(place, [edit.rect.topLeft, edit.rect.bottomRight]);
        resources['Font'] = <String, Object?>{
          'Helv': <String, Object?>{
            'Type': const PdfName('Font'),
            'Subtype': const PdfName('Type1'),
            'BaseFont': const PdfName('Helvetica'),
            'Encoding': const PdfName('WinAnsiEncoding'),
          },
        };
        draw.writeln(_colour(edit.color));
        final lines = _wrap(edit.text, edit.size, edit.rect.width);
        var baseline = edit.rect.top + edit.size;
        for (final line in lines) {
          if (baseline > edit.rect.bottom + edit.size * 0.3) break;
          // The reader's y runs down, so the text matrix flips it back up.
          draw.writeln(
            'BT /Helv ${_r(edit.size)} Tf 1 0 0 -1 '
            '${_r(edit.rect.left)} ${_r(baseline)} Tm '
            '${_winAnsiString(line)} Tj ET',
          );
          baseline += edit.size * 1.2;
        }
        annot = <String, Object?>{
          'Subtype': const PdfName('FreeText'),
          'Contents': _utf16(edit.text),
          'DA': PdfString(latin1.encode('/Helv ${_r(edit.size)} Tf ${_colour(edit.color)}')),
          'C': <Object?>[],
        };
      case ImageEdit():
        rect = _userRect(place, [edit.rect.topLeft, edit.rect.bottomRight]);
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
        final box = _userRect(place, points);
        rect = <double>[box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad];
        draw
          ..writeln(_colour(edit.color, stroke: true))
          ..writeln('${_r(edit.width)} w 1 J 1 j');
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
                  final (x, y) = _user(place, p);
                  return <Object?>[x, y];
                }(),
              ],
          ],
          'BS': <String, Object?>{'W': edit.width},
          'C': _colourArray(edit.color),
        };
      case HighlightEdit():
        if (edit.rects.isEmpty) {
          throw const PdfWriteError('A highlight covers nothing.');
        }
        rect = _userRect(place, [
          for (final r in edit.rects) ...[r.topLeft, r.bottomRight],
        ]);
        resources['ExtGState'] = <String, Object?>{
          'Mark': <String, Object?>{
            'Type': const PdfName('ExtGState'),
            'ca': 0.4,
            'BM': const PdfName('Multiply'),
          },
        };
        draw
          ..writeln('/Mark gs')
          ..writeln(_colour(edit.color));
        for (final r in edit.rects) {
          draw.writeln('${_r(r.left)} ${_r(r.top)} ${_r(r.width)} ${_r(r.height)} re f');
        }
        annot = <String, Object?>{
          'Subtype': const PdfName('Highlight'),
          'QuadPoints': _quads(place, edit.rects),
          'C': _colourArray(edit.color),
          'CA': 0.4,
        };
      case StrikeEdit():
        if (edit.rects.isEmpty) {
          throw const PdfWriteError('A strike through covers nothing.');
        }
        rect = _userRect(place, [
          for (final r in edit.rects) ...[r.topLeft, r.bottomRight],
        ]);
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
        };
    }
    draw.writeln('Q');
    final appearance = _form(rect, resources, ascii.encode(draw.toString()));
    final number = _next++;
    final dict = <String, Object?>{
      'Type': const PdfName('Annot'),
      ...annot,
      'Rect': rect,
      'P': page,
      'F': 4,
      'NM': PdfString(ascii.encode('quire-${DateTime.now().microsecondsSinceEpoch}-${_named++}')),
      'T': PdfString(ascii.encode('quire')),
      'M': PdfString(ascii.encode(_pdfDate(DateTime.now().toUtc()))),
      'AP': <String, Object?>{'N': PdfRef(appearance, 0)},
    };
    _objects[number] = _writer.object(number, 0, dict);
    _generations[number] = 0;
    return number;
  }

  /// A form XObject drawing [content] in the page's user space, its box the
  /// annotation's own, so the appearance lands exactly where it was drawn.
  int _form(List<double> bbox, Map<String, Object?> resources, Uint8List content) {
    final number = _next++;
    final body = file.encryptForObject(content, number, 0);
    final buffer = StringBuffer()..write('$number 0 obj\n');
    _writer.write(
      buffer,
      <String, Object?>{
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': bbox,
        'Resources': resources,
        'Length': body.length,
      },
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
    return number;
  }

  /// Each box as the four corners a text markup names: top left, top right,
  /// bottom left, bottom right, in user space.
  static List<Object?> _quads(List<double> m, List<Rect> rects) => <Object?>[
        for (final r in rects)
          for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight])
            ...() {
              final (x, y) = _user(m, p);
              return <Object?>[x, y];
            }(),
      ];

  /// [text] broken into lines that fit [width] at [size] in Helvetica, at
  /// the words where it can and inside a word where one is too long.
  static List<String> _wrap(String text, double size, double width) {
    double measure(String s) {
      var total = 0.0;
      for (final rune in s.runes) {
        final code = _winAnsiCode(rune);
        total += kHelvetica[code < kHelvetica.length ? code : 63] * size;
      }
      return total;
    }

    final out = <String>[];
    for (final paragraph in text.split('\n')) {
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

  static String _pdfDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return "D:${t.year}${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}Z";
  }
}
