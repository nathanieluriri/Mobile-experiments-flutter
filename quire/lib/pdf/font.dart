import 'dart:typed_data';
import 'document.dart';
import 'encodings.dart';
import 'lexer.dart';
import 'objects.dart';
import 'standard_metrics.dart';

/// One decoded character code: its unicode text and its advance in glyph
/// space (1/1000 em).
class CodeRun {
  const CodeRun(this.code, this.text, this.width);
  final int code;
  final String text;
  final double width;
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
  });

  final String baseFont;
  final bool twoByte;
  final double defaultWidth;
  final Map<int, double> widths;
  final Map<int, String> toUnicode;
  final Map<int, String> diffNames;
  final String baseEncoding;
  final bool isBold;
  final bool isItalic;
  final bool isSerif;
  final bool hasToUnicode;

  /// Splits a PDF string into codes and decodes each one.
  List<CodeRun> decode(Uint8List bytes) {
    final out = <CodeRun>[];
    if (twoByte) {
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        final code = (bytes[i] << 8) | bytes[i + 1];
        out.add(CodeRun(code, _text(code), widthOf(code)));
      }
      if (bytes.length.isOdd) {
        final code = bytes.last;
        out.add(CodeRun(code, _text(code), widthOf(code)));
      }
    } else {
      for (final code in bytes) {
        out.add(CodeRun(code, _text(code), widthOf(code)));
      }
    }
    return out;
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
      // Identity CID with no ToUnicode: nothing reliable to show.
      return code >= 0x20 && code < 0x7f ? String.fromCharCode(code) : '';
    }
    return String.fromCharCode(decodeSingleByte(code, baseEncoding));
  }

  /// Advance for [code] in glyph space, 1000 units to the em.
  ///
  /// A /Widths array wins. Failing that the standard fourteen tables answer,
  /// which is the only thing that keeps a font with no /Widths from laying out
  /// every glyph at the same flat advance.
  double widthOf(int code) {
    final w = widths[code];
    if (w != null) return w;
    final table = standardWidths(_normalizedStdName());
    if (table != null && code >= 0 && code < table.length) {
      return table[code] * 1000;
    }
    return defaultWidth;
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

  static PdfFont _loadSimple(PdfFile doc, Map<String, Object?> f, String base,
      String subtype, Map<int, String> toUni) {
    final widths = <int, double>{};
    final firstChar = (doc.resolve(f['FirstChar']) as num?)?.toInt() ?? 0;
    final wArr = doc.resolve(f['Widths']);
    if (wArr is List) {
      for (var i = 0; i < wArr.length; i++) {
        final v = doc.resolve(wArr[i]);
        if (v is num) widths[firstChar + i] = v.toDouble();
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
    return PdfFont(
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
    );
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
    // A CIDToGIDMap or a non-identity CMap would need more work; Identity-H
    // covers the overwhelming majority of Type0 fonts in the wild.
    final fd = doc.dict(d?['FontDescriptor']);
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
    );
  }
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
