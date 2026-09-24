import 'dart:typed_data';
import 'document.dart';
import 'encodings.dart';
import 'lexer.dart';
import 'objects.dart';
import 'standard_metrics.dart';
import 'truetype.dart';

/// One decoded character code: its unicode text, its advance in glyph space
/// (1/1000 em), and how many bytes of the string it took.
class CodeRun {
  const CodeRun(this.code, this.text, this.width, {this.bytes = 1});
  final int code;
  final String text;
  final double width;
  final int bytes;
}

/// A span of codes of one byte length, from a CMap's codespace.
class CodeSpace {
  const CodeSpace(this.bytes, this.low, this.high);
  final int bytes, low, high;
}

/// Everything the content interpreter needs from a /Font resource: how to cut
/// a string into codes, what unicode each code means, and how far it advances.
class PdfFont {
  PdfFont({
    required this.baseFont,
    required this.twoByte,
    required this.defaultWidth,
    required this.widths,
    required this.toUnicode,
    required this.diffNames,
    required this.baseEncoding,
    required this.isBold,
    required this.isItalic,
    required this.isSerif,
    required this.hasToUnicode,
    this.codeSpace = const [],
    this.cids = const {},
    this.cidsKnown = true,
    this.unicodeCodes = false,
    this.glyphText = const {},
    this.cidToGid,
    this.vertical = false,
    this.verticalAdvance = -1000,
    this.sizeScale = 1,
  });

  final String baseFont;
  final bool twoByte;
  final double defaultWidth;

  /// Advances in 1/1000 em, keyed by code for a simple font and by CID for a
  /// composite one.
  final Map<int, double> widths;
  final Map<int, String> toUnicode;
  final Map<int, String> diffNames;
  final String baseEncoding;
  final bool isBold;
  final bool isItalic;
  final bool isSerif;
  final bool hasToUnicode;

  /// How a composite font's strings are cut into codes. Empty means two bytes.
  final List<CodeSpace> codeSpace;

  /// Code to CID for a composite font whose CMap is not Identity.
  final Map<int, int> cids;

  /// False for a named CMap this reader has no table for, where a code's CID
  /// is unknown and every glyph takes the default width.
  final bool cidsKnown;

  /// True for the Unicode CMaps (UCS2, UTF16), whose codes are the text.
  final bool unicodeCodes;

  /// Glyph to text, read back out of the embedded font's own character map,
  /// for a composite font that came without a /ToUnicode.
  final Map<int, String> glyphText;

  /// CID to glyph, when the font says; null is Identity.
  final Uint8List? cidToGid;

  /// Vertical writing: each glyph moves the pen down by [verticalAdvance].
  final bool vertical;
  final double verticalAdvance;

  /// How big the letters are against the size the page asks for. Only a Type3
  /// font, which draws its glyphs at its own scale, is ever anything but 1.
  final double sizeScale;

  /// Splits a PDF string into codes and decodes each one.
  List<CodeRun> decode(Uint8List bytes) {
    final out = <CodeRun>[];
    var i = 0;
    while (i < bytes.length) {
      var n = _codeLength(bytes, i);
      if (i + n > bytes.length) n = bytes.length - i;
      var code = 0;
      for (var k = 0; k < n; k++) {
        code = (code << 8) | bytes[i + k];
      }
      out.add(CodeRun(code, _text(code), widthOf(code), bytes: n));
      i += n;
    }
    return out;
  }

  int _codeLength(Uint8List bytes, int at) {
    if (!twoByte) return 1;
    if (codeSpace.isEmpty) return 2;
    var code = 0;
    for (var n = 1; n <= 4 && at + n <= bytes.length; n++) {
      code = (code << 8) | bytes[at + n - 1];
      for (final r in codeSpace) {
        if (r.bytes == n && code >= r.low && code <= r.high) return n;
      }
    }
    return codeSpace.first.bytes;
  }

  int? _cid(int code) {
    if (!cidsKnown) return null;
    if (cids.isEmpty) return code;
    return cids[code] ?? 0;
  }

  String _text(int code) {
    final u = toUnicode[code];
    if (u != null) return u;
    final n = diffNames[code];
    if (n != null) {
      final cp = unicodeForGlyphName(n);
      if (cp != null) return String.fromCharCode(cp);
    }
    if (twoByte) {
      if (unicodeCodes) return String.fromCharCode(code);
      final cid = _cid(code);
      if (cid != null && glyphText.isNotEmpty) {
        final t = glyphText[_gid(cid)];
        if (t != null) return t;
      }
      // Identity CID with no ToUnicode: nothing reliable to show.
      return code >= 0x20 && code < 0x7f ? String.fromCharCode(code) : '';
    }
    return String.fromCharCode(decodeSingleByte(code, baseEncoding));
  }

  int _gid(int cid) {
    final map = cidToGid;
    if (map == null) return cid;
    final at = cid * 2;
    return at + 1 < map.length ? (map[at] << 8) | map[at + 1] : 0;
  }

  /// Advance for [code] in glyph space, 1000 units to the em.
  ///
  /// A /Widths array wins. Failing that the standard fourteen tables answer,
  /// which is the only thing that keeps a font with no /Widths from laying out
  /// every glyph at the same flat advance.
  double widthOf(int code) {
    if (twoByte) {
      final cid = _cid(code);
      return (cid == null ? null : widths[cid]) ?? defaultWidth;
    }
    final w = widths[code];
    if (w != null) return w;
    final table = standardWidths(_normalizedStdName());
    if (table != null && code >= 0 && code < table.length) {
      return table[code] * 1000;
    }
    return defaultWidth;
  }

  /// The width of the font's own space in 1/1000 em, or 0 when it has none.
  double get spaceWidth {
    if (!twoByte) {
      if (_text(32) == ' ') return widthOf(32);
      for (final e in diffNames.entries) {
        if (e.value == 'space') return widthOf(e.key);
      }
      return 0;
    }
    for (final e in toUnicode.entries) {
      if (e.value == ' ') return widthOf(e.key);
    }
    return 0;
  }

  String _normalizedStdName() {
    var n = baseFont.toLowerCase();
    final plus = n.indexOf('+');
    if (plus == 6) n = n.substring(7);
    if (n.startsWith('arial')) n = n.replaceFirst('arial', 'helvetica');
    if (n.startsWith('times')) {
      if (isBold && isItalic) return 'times-bolditalic';
      if (isBold) return 'times-bold';
      if (isItalic) return 'times-italic';
      return 'times-roman';
    }
    if (isStandardFontName(n)) return n;
    if (isSerif) {
      if (isBold && isItalic) return 'times-bolditalic';
      if (isBold) return 'times-bold';
      if (isItalic) return 'times-italic';
      return 'times-roman';
    }
    if (isBold && isItalic) return 'helvetica-boldoblique';
    if (isBold) return 'helvetica-bold';
    if (isItalic) return 'helvetica-oblique';
    return 'helvetica';
  }

  // ------------------------------------------------------------- building

  static PdfFont load(PdfFile doc, Map<String, Object?> f) {
    final subtype = (doc.resolve(f['Subtype']) as PdfName?)?.value ?? '';
    final base = (doc.resolve(f['BaseFont']) as PdfName?)?.value ?? '';
    final toUni = <int, String>{};
    final toUniStream = doc.resolve(f['ToUnicode']);
    if (toUniStream is PdfStream) {
      try {
        parseCMap(doc.decodeStream(toUniStream), toUni);
      } catch (_) {}
    }

    if (subtype == 'Type0') {
      return _loadType0(doc, f, base, toUni);
    }
    return _loadSimple(doc, f, base, subtype, toUni);
  }

  static TrueTypeFont? _embedded(PdfFile doc, Map<String, Object?>? fd) {
    final file = doc.resolve(fd?['FontFile2']);
    if (file is! PdfStream) return null;
    try {
      return TrueTypeFont.parse(doc.decodeStream(file));
    } catch (_) {
      return null;
    }
  }

  static List<double>? _numbers(PdfFile doc, Object? o, int length) {
    final v = doc.resolve(o);
    if (v is! List || v.length != length) return null;
    final out = <double>[];
    for (final e in v) {
      final n = doc.resolve(e);
      if (n is! num) return null;
      out.add(n.toDouble());
    }
    return out;
  }

  static PdfFont _loadSimple(PdfFile doc, Map<String, Object?> f, String base,
      String subtype, Map<int, String> toUni) {
    // A Type3 font states its widths in its own glyph space, which its
    // /FontMatrix takes to text space. Everything else is in 1/1000 em.
    var widthScale = 1.0;
    var sizeScale = 1.0;
    if (subtype == 'Type3') {
      final m = _numbers(doc, f['FontMatrix'], 6);
      if (m != null && m[0] != 0) widthScale = m[0].abs() * 1000;
      final box = _numbers(doc, f['FontBBox'], 4);
      if (m != null && box != null) {
        // The box around every glyph stands in for the em a Type3 font does
        // not have.
        final tall = (box[3] - box[1]).abs() * m[3].abs();
        if (tall > 0) sizeScale = tall.clamp(0.5, 2.0);
      }
    }
    final widths = <int, double>{};
    final firstChar = (doc.resolve(f['FirstChar']) as num?)?.toInt() ?? 0;
    final wArr = doc.resolve(f['Widths']);
    if (wArr is List) {
      for (var i = 0; i < wArr.length; i++) {
        final v = doc.resolve(wArr[i]);
        if (v is num) widths[firstChar + i] = v.toDouble() * widthScale;
      }
    }
    var baseEncoding = '';
    final diffNames = <int, String>{};
    final enc = doc.resolve(f['Encoding']);
    if (enc is PdfName) {
      baseEncoding = enc.value;
    } else if (enc is Map<String, Object?>) {
      baseEncoding =
          (doc.resolve(enc['BaseEncoding']) as PdfName?)?.value ?? '';
      final diff = doc.resolve(enc['Differences']);
      if (diff is List) {
        var code = 0;
        for (final e in diff) {
          final v = doc.resolve(e);
          if (v is num) {
            code = v.toInt();
          } else if (v is PdfName) {
            diffNames[code++] = v.value;
          }
        }
      }
    }
    final fd = doc.dict(f['FontDescriptor']);
    final flags = (doc.resolve(fd?['Flags']) as num?)?.toInt() ?? 0;
    final italicAngle = (doc.resolve(fd?['ItalicAngle']) as num?)?.toDouble() ?? 0;
    final weight = (doc.resolve(fd?['StemV']) as num?)?.toDouble() ?? 0;
    final lower = base.toLowerCase();
    final font = PdfFont(
      baseFont: base.isEmpty ? subtype : base,
      twoByte: false,
      defaultWidth: (doc.resolve(fd?['MissingWidth']) as num?)?.toDouble() ?? 500,
      widths: widths,
      toUnicode: toUni,
      diffNames: diffNames,
      baseEncoding: baseEncoding,
      isBold: lower.contains('bold') || (flags & 1 << 18) != 0 || weight > 120,
      isItalic: lower.contains('italic') ||
          lower.contains('oblique') ||
          italicAngle != 0 ||
          (flags & 1 << 6) != 0,
      isSerif: (flags & 1 << 1) != 0 ||
          lower.contains('times') ||
          lower.contains('serif') ||
          lower.contains('georgia') ||
          lower.contains('garamond'),
      hasToUnicode: toUni.isNotEmpty,
      sizeScale: sizeScale,
    );
    // /Widths is required, but a producer that leaves it out still embedded
    // the font, and the font knows how wide its glyphs are. The standard
    // fourteen tables are only a guess at a face that may not be Helvetica.
    if (widths.isEmpty) {
      final ttf = _embedded(doc, fd);
      if (ttf != null) {
        for (var code = 0; code < 256; code++) {
          final text = font._text(code);
          var gid = text.isEmpty ? 0 : ttf.glyphFor(text.runes.first);
          if (gid == 0) gid = ttf.glyphFor(0xF000 + code);
          if (gid == 0) gid = ttf.glyphFor(code);
          if (gid != 0) widths[code] = ttf.widthOf(gid);
        }
      }
    }
    return font;
  }

  static PdfFont _loadType0(PdfFile doc, Map<String, Object?> f, String base,
      Map<int, String> toUni) {
    final desc = doc.resolve(f['DescendantFonts']);
    Map<String, Object?>? d;
    if (desc is List && desc.isNotEmpty) d = doc.dict(desc.first);
    final widths = <int, double>{};
    final dw = (doc.resolve(d?['DW']) as num?)?.toDouble() ?? 1000;
    final w = doc.resolve(d?['W']);
    if (w is List) {
      var i = 0;
      while (i < w.length) {
        final a = doc.resolve(w[i]);
        if (a is! num) break;
        if (i + 1 >= w.length) break;
        final second = doc.resolve(w[i + 1]);
        if (second is List) {
          for (var k = 0; k < second.length; k++) {
            final v = doc.resolve(second[k]);
            if (v is num) widths[a.toInt() + k] = v.toDouble();
          }
          i += 2;
        } else if (second is num && i + 2 < w.length) {
          final v = doc.resolve(w[i + 2]);
          if (v is num) {
            for (var c = a.toInt(); c <= second.toInt() && c - a.toInt() < 65536; c++) {
              widths[c] = v.toDouble();
            }
          }
          i += 3;
        } else {
          break;
        }
      }
    }

    var codeSpace = const <CodeSpace>[];
    var cids = const <int, int>{};
    var cidsKnown = true;
    var unicodeCodes = false;
    var vertical = false;
    final enc = doc.resolve(f['Encoding']);
    if (enc is PdfName) {
      final name = enc.value;
      vertical = name.endsWith('-V');
      if (!name.startsWith('Identity-')) {
        // The Unicode CMaps name their codes by the text itself. Any other
        // named CMap needs a table of CIDs this reader does not carry.
        unicodeCodes = name.contains('UCS2') || name.contains('UTF16');
        cidsKnown = false;
      }
    } else if (enc is PdfStream) {
      final spaces = <CodeSpace>[];
      final map = <int, int>{};
      try {
        final cmap = parseCidCMap(doc.decodeStream(enc), spaces, map);
        vertical = cmap.vertical ||
            (doc.resolve(enc.dict['WMode']) as num?)?.toInt() == 1;
        if (!cmap.identity) {
          codeSpace = spaces;
          cids = map;
        }
      } catch (_) {}
    }
    var verticalAdvance = -1000.0;
    final dw2 = _numbers(doc, d?['DW2'], 2);
    if (dw2 != null && dw2[1] != 0) verticalAdvance = dw2[1];

    final fd = doc.dict(d?['FontDescriptor']);
    Map<int, String> glyphText = const {};
    Uint8List? cidToGid;
    if (toUni.isEmpty && !unicodeCodes) {
      final ttf = _embedded(doc, fd);
      if (ttf != null) glyphText = ttf.textByGlyph();
      final map = doc.resolve(d?['CIDToGIDMap']);
      if (map is PdfStream) {
        try {
          cidToGid = doc.decodeStream(map);
        } catch (_) {}
      }
    }
    final flags = (doc.resolve(fd?['Flags']) as num?)?.toInt() ?? 0;
    final italicAngle = (doc.resolve(fd?['ItalicAngle']) as num?)?.toDouble() ?? 0;
    final lower = base.toLowerCase();
    return PdfFont(
      baseFont: base,
      twoByte: true,
      defaultWidth: dw,
      widths: widths,
      toUnicode: toUni,
      diffNames: const {},
      baseEncoding: '',
      isBold: lower.contains('bold') || (flags & 1 << 18) != 0,
      isItalic: lower.contains('italic') ||
          lower.contains('oblique') ||
          italicAngle != 0 ||
          (flags & 1 << 6) != 0,
      isSerif: (flags & 1 << 1) != 0 ||
          lower.contains('times') ||
          lower.contains('serif'),
      hasToUnicode: toUni.isNotEmpty,
      codeSpace: codeSpace,
      cids: cids,
      cidsKnown: cidsKnown,
      unicodeCodes: unicodeCodes,
      glyphText: glyphText,
      cidToGid: cidToGid,
      vertical: vertical,
      verticalAdvance: verticalAdvance,
    );
  }
}

/// What an embedded CMap said about itself beyond its tables.
class CidCMapInfo {
  const CidCMapInfo({required this.identity, required this.vertical});

  /// True when every code is its own CID, so the tables add nothing.
  final bool identity;
  final bool vertical;
}

/// Reads the codespace and the code to CID tables of an embedded CMap.
CidCMapInfo parseCidCMap(
    Uint8List data, List<CodeSpace> spaces, Map<int, int> cids) {
  final lx = PdfLexer(data);
  var identity = false;
  var vertical = false;
  Object? last;
  while (!lx.atEnd) {
    final o = lx.parseObject();
    if (o == null) break;
    if (o is PdfKeyword) {
      switch (o.value) {
        case 'begincodespacerange':
          while (!lx.atEnd) {
            final a = lx.parseObject();
            if (a is! PdfString) break;
            final b = lx.parseObject();
            if (b is! PdfString) break;
            spaces.add(CodeSpace(a.bytes.length, _codeOf(a), _codeOf(b)));
          }
          break;
        case 'begincidrange':
          while (!lx.atEnd) {
            final a = lx.parseObject();
            if (a is! PdfString) break;
            final b = lx.parseObject();
            final c = lx.parseObject();
            if (b is! PdfString || c is! num) break;
            final lo = _codeOf(a), hi = _codeOf(b);
            for (var k = 0; k <= hi - lo && k < 65536; k++) {
              cids[lo + k] = c.toInt() + k;
            }
          }
          break;
        case 'begincidchar':
          while (!lx.atEnd) {
            final a = lx.parseObject();
            if (a is! PdfString) break;
            final c = lx.parseObject();
            if (c is! num) break;
            cids[_codeOf(a)] = c.toInt();
          }
          break;
        case 'usecmap':
          if (last is PdfName) {
            identity = last.value.startsWith('Identity-');
            vertical = last.value.endsWith('-V');
          }
          break;
        case 'def':
          break;
      }
    } else if (o is PdfName && o.value == 'WMode') {
      final v = lx.parseObject();
      if (v is num && v.toInt() == 1) vertical = true;
    }
    last = o;
  }
  if (cids.isEmpty && spaces.isEmpty) identity = true;
  return CidCMapInfo(identity: identity && cids.isEmpty, vertical: vertical);
}

/// Parses the bfchar / bfrange sections of a ToUnicode CMap.
void parseCMap(Uint8List data, Map<int, String> out) {
  final lx = PdfLexer(data);
  final stack = <Object?>[];
  while (!lx.atEnd) {
    final o = lx.parseObject();
    if (o == null) break;
    if (o is PdfKeyword) {
      switch (o.value) {
        case 'beginbfchar':
          stack.clear();
          _readBfChar(lx, out);
          break;
        case 'beginbfrange':
          stack.clear();
          _readBfRange(lx, out);
          break;
        default:
          stack.clear();
      }
    } else {
      stack.add(o);
      if (stack.length > 8) stack.removeAt(0);
    }
  }
}

int _codeOf(PdfString s) {
  var v = 0;
  for (final b in s.bytes) {
    v = (v << 8) | b;
  }
  return v;
}

String _utf16be(Uint8List b) {
  if (b.isEmpty) return '';
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add((b[i] << 8) | b[i + 1]);
  }
  if (units.isEmpty) return String.fromCharCode(b.first);
  return String.fromCharCodes(units);
}

void _readBfChar(PdfLexer lx, Map<int, String> out) {
  while (!lx.atEnd) {
    final a = lx.parseObject();
    if (a is PdfKeyword) return;
    final b = lx.parseObject();
    if (a is PdfString && b is PdfString) {
      out[_codeOf(a)] = _utf16be(b.bytes);
    } else if (b is PdfKeyword) {
      return;
    }
  }
}

void _readBfRange(PdfLexer lx, Map<int, String> out) {
  while (!lx.atEnd) {
    final a = lx.parseObject();
    if (a is PdfKeyword) return;
    final b = lx.parseObject();
    final c = lx.parseObject();
    if (a is! PdfString || b is! PdfString) return;
    final lo = _codeOf(a), hi = _codeOf(b);
    if (hi < lo || hi - lo > 65535) return;
    if (c is PdfString) {
      final units = <int>[];
      for (var i = 0; i + 1 < c.bytes.length; i += 2) {
        units.add((c.bytes[i] << 8) | c.bytes[i + 1]);
      }
      if (units.isEmpty) continue;
      for (var k = 0; k <= hi - lo; k++) {
        final u = List<int>.from(units);
        u[u.length - 1] = u.last + k;
        out[lo + k] = String.fromCharCodes(u);
      }
    } else if (c is List) {
      for (var k = 0; k < c.length && lo + k <= hi; k++) {
        final e = c[k];
        if (e is PdfString) out[lo + k] = _utf16be(e.bytes);
      }
    }
  }
}
