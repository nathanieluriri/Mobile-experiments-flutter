import 'dart:typed_data';

import 'encodings.dart';

/// Enough of a TrueType file to set type with it and to embed it in a PDF.
///
/// This is the reading half of writing a PDF. A page file names glyphs, not
/// letters, so nothing can be set until the font has been asked which glyph
/// each character is and how wide that glyph runs. Everything here comes
/// straight out of the font's own tables, because the alternative is guessing
/// at metrics and producing a page whose lines do not break where the app
/// thought they would.
class TrueTypeFont {
  TrueTypeFont._(
    this.bytes,
    this._tables,
    this.unitsPerEm,
    this.numGlyphs,
    this.ascender,
    this.descender,
    this.bbox,
    this._longLoca,
    this._widths,
    this._cmap,
  );

  /// Reads [bytes] as a font, or throws [FontFormatError] if it is not one.
  factory TrueTypeFont.parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 12) throw const FontFormatError('the file is too short');
    final version = data.getUint32(0);
    // 0x00010000 is TrueType outlines, 'true' is the same thing on Apple's
    // side. 'OTTO' is CFF outlines, which a FontFile2 cannot carry.
    if (version != 0x00010000 && version != 0x74727565) {
      throw FontFormatError(
        version == 0x4F54544F
            ? 'the font has CFF outlines, which this writer cannot embed'
            : 'the file is not TrueType',
      );
    }
    final count = data.getUint16(4);
    final tables = <String, _Table>{};
    for (var i = 0; i < count; i++) {
      final at = 12 + i * 16;
      if (at + 16 > bytes.length) break;
      final tag = String.fromCharCodes(bytes.sublist(at, at + 4));
      tables[tag] = _Table(data.getUint32(at + 8), data.getUint32(at + 12));
    }

    _Table need(String tag) {
      final table = tables[tag];
      if (table == null) throw FontFormatError('the font has no $tag table');
      return table;
    }

    final head = need('head').offset;
    final unitsPerEm = data.getUint16(head + 18);
    final bbox = <int>[
      data.getInt16(head + 36),
      data.getInt16(head + 38),
      data.getInt16(head + 40),
      data.getInt16(head + 42),
    ];
    final longLoca = data.getInt16(head + 50) != 0;

    final hhea = need('hhea').offset;
    final ascender = data.getInt16(hhea + 4);
    final descender = data.getInt16(hhea + 6);
    final metrics = data.getUint16(hhea + 34);

    final numGlyphs = data.getUint16(need('maxp').offset + 4);

    final hmtx = need('hmtx').offset;
    final widths = Uint16List(numGlyphs);
    var last = 0;
    for (var gid = 0; gid < numGlyphs; gid++) {
      if (gid < metrics) {
        final at = hmtx + gid * 4;
        if (at + 2 > bytes.length) break;
        last = data.getUint16(at);
      }
      widths[gid] = last;
    }

    return TrueTypeFont._(
      bytes,
      tables,
      unitsPerEm == 0 ? 1000 : unitsPerEm,
      numGlyphs,
      ascender,
      descender,
      bbox,
      longLoca,
      widths,
      // A font may honestly have no character map: a subset embedded in a page
      // file addresses its glyphs by number and carries none. Such a font can
      // still be measured and still be embedded again; it just cannot be told
      // which glyph a letter is, which is what [glyphFor] answers with the
      // empty box.
      tables['cmap'] == null
          ? const <int, int>{}
          : _readCmap(data, bytes, tables['cmap']!.offset),
    );
  }

  /// The whole file, which is what a subset is cut out of.
  final Uint8List bytes;

  final Map<String, _Table> _tables;

  /// The em square in font units. Every metric here is in those, and the PDF
  /// wants thousandths of an em, which is what [widthOf] converts to.
  final int unitsPerEm;

  final int numGlyphs;
  final int ascender;
  final int descender;

  /// xMin, yMin, xMax, yMax in font units.
  final List<int> bbox;

  final bool _longLoca;
  final Uint16List _widths;
  final Map<int, int> _cmap;

  /// The glyph [rune] is drawn with, or 0 when the font does not have one.
  ///
  /// Glyph 0 is the empty box every font carries for exactly this, so a
  /// character the font cannot set comes out as the box rather than as
  /// nothing: a reader who sees a box knows something was there.
  int glyphFor(int rune) => _cmap[rune] ?? 0;

  /// The character each glyph draws, for reading text back out of a page
  /// whose font came without a map of its own. Codes from a symbol table are
  /// not text and are left out.
  ///
  /// Where the character map says nothing, the glyph's own name in the
  /// `post` table is read instead.
  Map<int, String> textByGlyph() {
    final out = <int, String>{};
    for (final e in _cmap.entries) {
      if (e.key >= 0xF000 && e.key <= 0xF0FF) continue;
      out.putIfAbsent(e.value, () => String.fromCharCode(e.key));
    }
    final names = glyphNames;
    if (names != null) {
      for (var gid = 0; gid < names.length; gid++) {
        if (out.containsKey(gid)) continue;
        final name = names[gid];
        final text = name == null ? null : textForGlyphName(name);
        if (text != null && text.trim().isNotEmpty) out[gid] = text;
      }
    }
    return out;
  }

  /// Each glyph's name from the font's `post` table, or null when it names
  /// none. A subset embedded without a character map often still carries
  /// the names, and a name is enough to know the character.
  late final List<String?>? glyphNames = _readPostNames();

  List<String?>? _readPostNames() {
    final post = _tables['post'];
    if (post == null || post.length < 34) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(post.offset) != 0x00020000) return null;
    final end = post.offset + post.length;
    if (end > bytes.length) return null;
    final count = data.getUint16(post.offset + 32);
    var at = post.offset + 34;
    if (at + count * 2 > end) return null;
    final indices = <int>[
      for (var i = 0; i < count; i++) data.getUint16(at + i * 2),
    ];
    at += count * 2;
    final own = <String>[];
    while (at < end) {
      final length = bytes[at++];
      if (at + length > end) break;
      own.add(String.fromCharCodes(bytes, at, at + length));
      at += length;
    }
    return <String?>[
      for (final index in indices)
        index < _macGlyphNames.length
            ? _macGlyphNames[index]
            : (index - _macGlyphNames.length < own.length
                ? own[index - _macGlyphNames.length]
                : null),
    ];
  }

  /// True when the font has a glyph of its own for [rune].
  bool covers(int rune) => _cmap.containsKey(rune);

  /// How far the pen moves after [gid], in thousandths of an em.
  double widthOf(int gid) => gid >= _widths.length
      ? 0
      : _widths[gid] * 1000 / unitsPerEm;

  /// The advance of [text] set at [size] points.
  double measure(String text, double size) {
    var total = 0.0;
    for (final rune in text.runes) {
      total += widthOf(glyphFor(rune));
    }
    return total * size / 1000;
  }

  /// A font holding only the glyphs in [keep], for embedding.
  ///
  /// The glyph numbering does not change: unused glyphs are emptied rather
  /// than removed, so every index the rest of the file states stays true and
  /// nothing has to be renumbered. It is the smaller half of the saving and
  /// all of the safety, because the outlines are nearly the whole file.
  ///
  /// Only the tables a PDF needs to rasterise the glyphs come across. A name
  /// table, a cmap and the layout tables are all weight the reader will never
  /// consult, since the page addresses glyphs by number.
  Uint8List subset(Set<int> keep) {
    final wanted = <int>{0};
    for (final gid in keep) {
      if (gid >= 0 && gid < numGlyphs) _withComponents(gid, wanted);
    }

    final glyf = _tables['glyf'];
    final loca = _tables['loca'];
    if (glyf == null || loca == null) return bytes;

    final offsets = _locaOffsets(loca);
    final body = BytesBuilder();
    final newLoca = <int>[0];
    for (var gid = 0; gid < numGlyphs; gid++) {
      if (wanted.contains(gid)) {
        final from = glyf.offset + offsets[gid];
        final to = glyf.offset + offsets[gid + 1];
        if (to > from && to <= bytes.length) {
          body.add(bytes.sublist(from, to));
        }
      }
      // A glyph is padded to a four byte boundary, which is what lets a short
      // loca table state its offsets in halves.
      while (body.length % 4 != 0) {
        body.addByte(0);
      }
      newLoca.add(body.length);
    }

    final glyfOut = body.toBytes();
    final longLoca = glyfOut.length > 0x1FFFE;
    final locaOut = _writeLoca(newLoca, longLoca);

    final head = Uint8List.fromList(
      bytes.sublist(
        _tables['head']!.offset,
        _tables['head']!.offset + _tables['head']!.length,
      ),
    );
    ByteData.sublistView(head).setInt16(50, longLoca ? 1 : 0);
    // The file checksum is over the whole file, which is not known until the
    // file is built. Zero is what every subsetter writes and what every
    // rasteriser accepts.
    ByteData.sublistView(head).setUint32(8, 0);

    final parts = <String, Uint8List>{
      'glyf': glyfOut,
      'head': head,
      'loca': locaOut,
    };
    for (final tag in const <String>['cvt ', 'fpgm', 'hhea', 'hmtx', 'maxp',
        'prep']) {
      final table = _tables[tag];
      if (table == null) continue;
      final end = table.offset + table.length;
      if (end > bytes.length) continue;
      parts[tag] = Uint8List.fromList(bytes.sublist(table.offset, end));
    }
    return _buildSfnt(parts);
  }

  /// A composite glyph is drawn out of other glyphs, so keeping it without
  /// keeping its parts keeps an outline of nothing.
  void _withComponents(int gid, Set<int> into, [int depth = 0]) {
    if (!into.add(gid) || depth > 5) return;
    final glyf = _tables['glyf'];
    final loca = _tables['loca'];
    if (glyf == null || loca == null) return;
    final offsets = _locaOffsets(loca);
    if (gid + 1 >= offsets.length) return;
    final start = glyf.offset + offsets[gid];
    if (offsets[gid + 1] <= offsets[gid] || start + 10 > bytes.length) return;
    final data = ByteData.sublistView(bytes);
    if (data.getInt16(start) >= 0) return;

    var at = start + 10;
    while (at + 4 <= bytes.length) {
      final flags = data.getUint16(at);
      final part = data.getUint16(at + 2);
      _withComponents(part, into, depth + 1);
      at += 4;
      at += (flags & 0x0001) != 0 ? 4 : 2;
      if ((flags & 0x0008) != 0) {
        at += 2;
      } else if ((flags & 0x0040) != 0) {
        at += 4;
      } else if ((flags & 0x0080) != 0) {
        at += 8;
      }
      if ((flags & 0x0020) == 0) break;
    }
  }

  List<int>? _locaCache;

  List<int> _locaOffsets(_Table loca) {
    final cached = _locaCache;
    if (cached != null) return cached;
    final data = ByteData.sublistView(bytes);
    final out = <int>[];
    for (var i = 0; i <= numGlyphs; i++) {
      final at = loca.offset + (_longLoca ? i * 4 : i * 2);
      if (at + (_longLoca ? 4 : 2) > bytes.length) {
        out.add(out.isEmpty ? 0 : out.last);
        continue;
      }
      out.add(_longLoca ? data.getUint32(at) : data.getUint16(at) * 2);
    }
    return _locaCache = out;
  }

  static Uint8List _writeLoca(List<int> offsets, bool long) {
    final out = Uint8List(offsets.length * (long ? 4 : 2));
    final data = ByteData.sublistView(out);
    for (var i = 0; i < offsets.length; i++) {
      if (long) {
        data.setUint32(i * 4, offsets[i]);
      } else {
        data.setUint16(i * 2, offsets[i] ~/ 2);
      }
    }
    return out;
  }

  /// Wraps [parts] back up as a font file, tables in tag order the way the
  /// specification asks for.
  static Uint8List _buildSfnt(Map<String, Uint8List> parts) {
    final tags = parts.keys.toList()..sort();
    final count = tags.length;
    var power = 1;
    var selector = 0;
    while (power * 2 <= count) {
      power *= 2;
      selector++;
    }
    final directory = 12 + count * 16;
    var at = directory;
    final offsets = <String, int>{};
    for (final tag in tags) {
      offsets[tag] = at;
      at += parts[tag]!.length;
      while (at % 4 != 0) {
        at++;
      }
    }

    final out = Uint8List(at);
    final data = ByteData.sublistView(out);
    data.setUint32(0, 0x00010000);
    data.setUint16(4, count);
    data.setUint16(6, power * 16);
    data.setUint16(8, selector);
    data.setUint16(10, count * 16 - power * 16);
    for (var i = 0; i < count; i++) {
      final tag = tags[i];
      final bytes = parts[tag]!;
      final record = 12 + i * 16;
      out.setRange(record, record + 4, tag.codeUnits);
      data.setUint32(record + 4, _checksum(bytes));
      data.setUint32(record + 8, offsets[tag]!);
      data.setUint32(record + 12, bytes.length);
      out.setRange(offsets[tag]!, offsets[tag]! + bytes.length, bytes);
    }
    return out;
  }

  static int _checksum(Uint8List table) {
    var sum = 0;
    for (var i = 0; i < table.length; i += 4) {
      var word = 0;
      for (var b = 0; b < 4; b++) {
        word = (word << 8) | (i + b < table.length ? table[i + b] : 0);
      }
      sum = (sum + word) & 0xFFFFFFFF;
    }
    return sum;
  }

  /// The character to glyph map, from the best table the font offers.
  ///
  /// Format 12 first, because it reaches past the basic plane, then format 4,
  /// which is the one every font has. A font with neither is a font this
  /// writer cannot set with.
  static Map<int, int> _readCmap(ByteData data, Uint8List bytes, int start) {
    if (start + 4 > bytes.length) return const <int, int>{};
    final count = data.getUint16(start + 2);
    var best = -1;
    var bestScore = -1;
    for (var i = 0; i < count; i++) {
      final at = start + 4 + i * 8;
      if (at + 8 > bytes.length) break;
      final platform = data.getUint16(at);
      final encoding = data.getUint16(at + 2);
      final offset = start + data.getUint32(at + 4);
      if (offset + 2 > bytes.length) continue;
      final format = data.getUint16(offset);
      final score = switch ((platform, encoding, format)) {
        (3, 10, 12) => 5,
        (0, _, 12) => 4,
        (3, 1, 4) => 3,
        (0, _, 4) => 2,
        // A symbol font's codes sit at 0xF000 up, and an old Mac table maps
        // single bytes: neither is Unicode, but a page's embedded subset may
        // carry nothing else.
        (3, 0, 4) => 1,
        (1, 0, 0) => 0,
        _ => -1,
      };
      if (score > bestScore) {
        bestScore = score;
        best = offset;
      }
    }
    if (best < 0) return const <int, int>{};
    return switch (data.getUint16(best)) {
      12 => _readCmap12(data, bytes, best),
      4 => _readCmap4(data, bytes, best),
      0 => _readCmap0(bytes, best),
      _ => const <int, int>{},
    };
  }

  static Map<int, int> _readCmap0(Uint8List bytes, int at) {
    final out = <int, int>{};
    for (var code = 0; code < 256 && at + 6 + code < bytes.length; code++) {
      final gid = bytes[at + 6 + code];
      if (gid != 0) out[code] = gid;
    }
    return out;
  }

  static Map<int, int> _readCmap4(ByteData data, Uint8List bytes, int at) {
    final out = <int, int>{};
    final segments = data.getUint16(at + 6) ~/ 2;
    final ends = at + 14;
    final starts = ends + segments * 2 + 2;
    final deltas = starts + segments * 2;
    final ranges = deltas + segments * 2;
    for (var s = 0; s < segments; s++) {
      if (ranges + s * 2 + 2 > bytes.length) break;
      final end = data.getUint16(ends + s * 2);
      final start = data.getUint16(starts + s * 2);
      final delta = data.getInt16(deltas + s * 2);
      final rangeAt = data.getUint16(ranges + s * 2);
      if (start > end) continue;
      for (var code = start; code <= end && code != 0xFFFF; code++) {
        int gid;
        if (rangeAt == 0) {
          gid = (code + delta) & 0xFFFF;
        } else {
          final index = ranges + s * 2 + rangeAt + (code - start) * 2;
          if (index + 2 > bytes.length) continue;
          gid = data.getUint16(index);
          if (gid != 0) gid = (gid + delta) & 0xFFFF;
        }
        if (gid != 0) out[code] = gid;
      }
    }
    return out;
  }

  static Map<int, int> _readCmap12(ByteData data, Uint8List bytes, int at) {
    final out = <int, int>{};
    if (at + 16 > bytes.length) return out;
    final groups = data.getUint32(at + 12);
    for (var g = 0; g < groups; g++) {
      final record = at + 16 + g * 12;
      if (record + 12 > bytes.length) break;
      final start = data.getUint32(record);
      final end = data.getUint32(record + 4);
      final gid = data.getUint32(record + 8);
      if (end < start || end - start > 0x10000) continue;
      for (var code = start; code <= end; code++) {
        out[code] = gid + (code - start);
      }
    }
    return out;
  }
}

/// A font this writer cannot set with, and why.
class FontFormatError implements Exception {
  const FontFormatError(this.message);
  final String message;

  @override
  String toString() => 'FontFormatError: $message';
}

class _Table {
  const _Table(this.offset, this.length);
  final int offset;
  final int length;
}

/// The 258 glyph names a `post` table of format 2 numbers without spelling
/// them out, in Apple's order.
const _macGlyphNames = <String>[
  '.notdef', '.null', 'nonmarkingreturn', 'space', 'exclam', 'quotedbl',
  'numbersign', 'dollar', 'percent', 'ampersand', 'quotesingle', 'parenleft',
  'parenright', 'asterisk', 'plus', 'comma', 'hyphen', 'period', 'slash',
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'colon', 'semicolon', 'less', 'equal', 'greater', 'question', 'at',
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O',
  'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'bracketleft',
  'backslash', 'bracketright', 'asciicircum', 'underscore', 'grave', 'a',
  'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
  'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'braceleft', 'bar',
  'braceright', 'asciitilde', 'Adieresis', 'Aring', 'Ccedilla', 'Eacute',
  'Ntilde', 'Odieresis', 'Udieresis', 'aacute', 'agrave', 'acircumflex',
  'adieresis', 'atilde', 'aring', 'ccedilla', 'eacute', 'egrave',
  'ecircumflex', 'edieresis', 'iacute', 'igrave', 'icircumflex', 'idieresis',
  'ntilde', 'oacute', 'ograve', 'ocircumflex', 'odieresis', 'otilde',
  'uacute', 'ugrave', 'ucircumflex', 'udieresis', 'dagger', 'degree', 'cent',
  'sterling', 'section', 'bullet', 'paragraph', 'germandbls', 'registered',
  'copyright', 'trademark', 'acute', 'dieresis', 'notequal', 'AE', 'Oslash',
  'infinity', 'plusminus', 'lessequal', 'greaterequal', 'yen', 'mu',
  'partialdiff', 'summation', 'product', 'pi', 'integral', 'ordfeminine',
  'ordmasculine', 'Omega', 'ae', 'oslash', 'questiondown', 'exclamdown',
  'logicalnot', 'radical', 'florin', 'approxequal', 'Delta', 'guillemotleft',
  'guillemotright', 'ellipsis', 'nonbreakingspace', 'Agrave', 'Atilde',
  'Otilde', 'OE', 'oe', 'endash', 'emdash', 'quotedblleft', 'quotedblright',
  'quoteleft', 'quoteright', 'divide', 'lozenge', 'ydieresis', 'Ydieresis',
  'fraction', 'currency', 'guilsinglleft', 'guilsinglright', 'fi', 'fl',
  'daggerdbl', 'periodcentered', 'quotesinglbase', 'quotedblbase',
  'perthousand', 'Acircumflex', 'Ecircumflex', 'Aacute', 'Edieresis',
  'Egrave', 'Iacute', 'Icircumflex', 'Idieresis', 'Igrave', 'Oacute',
  'Ocircumflex', 'apple', 'Ograve', 'Uacute', 'Ucircumflex', 'Ugrave',
  'dotlessi', 'circumflex', 'tilde', 'macron', 'breve', 'dotaccent', 'ring',
  'cedilla', 'hungarumlaut', 'ogonek', 'caron', 'Lslash', 'lslash', 'Scaron',
  'scaron', 'Zcaron', 'zcaron', 'brokenbar', 'Eth', 'eth', 'Yacute',
  'yacute', 'Thorn', 'thorn', 'minus', 'multiply', 'onesuperior',
  'twosuperior', 'threesuperior', 'onehalf', 'onequarter', 'threequarters',
  'franc', 'Gbreve', 'gbreve', 'Idotaccent', 'Scedilla', 'scedilla',
  'Cacute', 'cacute', 'Ccaron', 'ccaron', 'dcroat',
];
