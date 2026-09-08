import 'dart:typed_data';
import 'objects.dart';

const int _kLf = 0x0a, _kCr = 0x0d, _kTab = 0x09, _kSpace = 0x20;
const int _kFf = 0x0c, _kNul = 0x00;

bool isWhite(int c) =>
    c == _kSpace || c == _kLf || c == _kCr || c == _kTab || c == _kFf || c == _kNul;
bool isDelim(int c) =>
    c == 0x28 || c == 0x29 || c == 0x3c || c == 0x3e || c == 0x5b ||
    c == 0x5d || c == 0x7b || c == 0x7d || c == 0x2f || c == 0x25;
bool isRegular(int c) => !isWhite(c) && !isDelim(c);

/// Marker returned for a bare keyword the caller must interpret (operators,
/// `obj`, `endobj`, `stream`, `R`, ...).
class PdfKeyword {
  const PdfKeyword(this.value);
  final String value;
  @override
  String toString() => 'kw($value)';
}

/// Tokeniser + object parser shared by the file body and content streams.
class PdfLexer {
  PdfLexer(this.bytes, [this.pos = 0]);
  final Uint8List bytes;
  int pos;

  int get length => bytes.length;
  bool get atEnd => pos >= bytes.length;

  void skipWhitespace() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        // comment to end of line
        while (pos < bytes.length && bytes[pos] != _kLf && bytes[pos] != _kCr) {
          pos++;
        }
      } else {
        return;
      }
    }
  }

  /// Parses one object. Returns [PdfKeyword] for bare keywords/operators.
  Object? parseObject() {
    skipWhitespace();
    if (atEnd) return null;
    final c = bytes[pos];
    switch (c) {
      case 0x2f:
        return _name();
      case 0x28:
        return _literalString();
      case 0x5b:
        pos++;
        final list = <Object?>[];
        while (true) {
          skipWhitespace();
          if (atEnd) break;
          if (bytes[pos] == 0x5d) {
            pos++;
            break;
          }
          final o = parseObject();
          if (o is PdfKeyword && o.value == 'R') {
            _collapseRef(list);
          } else {
            list.add(o);
          }
        }
        return list;
      case 0x3c:
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3c) return _dict();
        return _hexString();
      case 0x5d:
      case 0x3e:
      case 0x7b:
      case 0x7d:
      case 0x29:
        pos++;
        return const PdfKeyword('');
    }
    if (c == 0x2b || c == 0x2d || c == 0x2e || (c >= 0x30 && c <= 0x39)) {
      return _number();
    }
    return _keyword();
  }

  void _collapseRef(List<Object?> list) {
    if (list.length >= 2 &&
        list[list.length - 1] is int &&
        list[list.length - 2] is int) {
      final gen = list.removeLast() as int;
      final num_ = list.removeLast() as int;
      list.add(PdfRef(num_, gen));
    }
  }

  PdfName _name() {
    pos++; // slash
    final sb = StringBuffer();
    while (pos < bytes.length && isRegular(bytes[pos])) {
      var ch = bytes[pos];
      if (ch == 0x23 && pos + 2 < bytes.length) {
        final hex = _hexVal(bytes[pos + 1]) * 16 + _hexVal(bytes[pos + 2]);
        if (hex >= 0) {
          sb.writeCharCode(hex);
          pos += 3;
          continue;
        }
      }
      sb.writeCharCode(ch);
      pos++;
    }
    return PdfName(sb.toString());
  }

  static int _hexVal(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x37;
    if (c >= 0x61 && c <= 0x66) return c - 0x57;
    return -1;
  }

  PdfString _literalString() {
    pos++; // (
    final out = <int>[];
    var depth = 1;
    while (pos < bytes.length) {
      var c = bytes[pos++];
      if (c == 0x5c) {
        if (pos >= bytes.length) break;
        final e = bytes[pos++];
        switch (e) {
          case 0x6e: out.add(_kLf); break;
          case 0x72: out.add(_kCr); break;
          case 0x74: out.add(_kTab); break;
          case 0x62: out.add(0x08); break;
          case 0x66: out.add(_kFf); break;
          case _kLf: break;
          case _kCr:
            if (pos < bytes.length && bytes[pos] == _kLf) pos++;
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var i = 0; i < 2; i++) {
                if (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x37) {
                  v = v * 8 + (bytes[pos++] - 0x30);
                } else {
                  break;
                }
              }
              out.add(v & 0xff);
            } else {
              out.add(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.add(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.add(c);
      } else {
        out.add(c);
      }
    }
    return PdfString(Uint8List.fromList(out));
  }

  PdfString _hexString() {
    pos++; // <
    final out = <int>[];
    int? hi;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x3e) break;
      final v = _hexVal(c);
      if (v < 0) continue;
      if (hi == null) {
        hi = v;
      } else {
        out.add(hi * 16 + v);
        hi = null;
      }
    }
    if (hi != null) out.add(hi * 16);
    return PdfString(Uint8List.fromList(out));
  }

  Map<String, Object?> _dict() {
    pos += 2; // <<
    final map = <String, Object?>{};
    while (true) {
      skipWhitespace();
      if (atEnd) break;
      if (bytes[pos] == 0x3e) {
        pos++;
        if (!atEnd && bytes[pos] == 0x3e) pos++;
        break;
      }
      if (bytes[pos] != 0x2f) {
        // Malformed: skip one object to make progress.
        final junk = parseObject();
        if (junk == null) break;
        continue;
      }
      final key = _name().value;
      final pending = <Object?>[];
      while (true) {
        skipWhitespace();
        if (atEnd) break;
        if (bytes[pos] == 0x3e) break;
        if (bytes[pos] == 0x2f && pending.isNotEmpty) break;
        final v = parseObject();
        if (v is PdfKeyword && v.value == 'R') {
          _collapseRef(pending);
        } else {
          pending.add(v);
        }
        if (pending.length == 1 && pending[0] is! int) break;
        if (pending.length >= 3) break;
      }
      map[key] = pending.isEmpty ? null : pending.first;
    }
    return map;
  }

  Object _number() {
    final start = pos;
    var isReal = false;
    if (bytes[pos] == 0x2b || bytes[pos] == 0x2d) pos++;
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (c >= 0x30 && c <= 0x39) {
        pos++;
      } else if (c == 0x2e || c == 0x2d || c == 0x2b || c == 0x45 || c == 0x65) {
        isReal = true;
        pos++;
      } else {
        break;
      }
    }
    final s = String.fromCharCodes(bytes.sublist(start, pos));
    if (!isReal) return int.tryParse(s) ?? 0;
    return double.tryParse(s) ?? _looseDouble(s);
  }

  static double _looseDouble(String s) {
    final m = RegExp(r'^[+-]?\d*\.?\d*').firstMatch(s)?.group(0) ?? '';
    return double.tryParse(m) ?? 0;
  }

  PdfKeyword _keyword() {
    final start = pos;
    while (pos < bytes.length && isRegular(bytes[pos])) {
      pos++;
    }
    if (pos == start) pos++;
    return PdfKeyword(String.fromCharCodes(bytes.sublist(start, pos)));
  }
}
