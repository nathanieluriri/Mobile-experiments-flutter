import 'dart:typed_data';
import 'filters.dart';
import 'lexer.dart';
import 'objects.dart';

class XrefEntry {
  XrefEntry.offset(this.offset)
      : inObjStm = null,
        indexInStm = 0;
  XrefEntry.compressed(this.inObjStm, this.indexInStm) : offset = -1;
  final int offset;
  final int? inObjStm;
  final int indexInStm;
}

/// A random access PDF file: the xref chain, object resolution, stream
/// decoding and the page tree.
///
/// [open] never throws. A file whose xref is unreachable or whose catalogue is
/// missing falls through to [_scanAllObjects], which is why a damaged download
/// still opens to its real pages instead of an error sheet.
class PdfFile {
  PdfFile._(this.bytes);
  final Uint8List bytes;

  final Map<int, XrefEntry> xref = {};
  final Map<int, Object?> _cache = {};
  final Map<int, List<Object?>> _objStmCache = {};
  Map<String, Object?> trailer = {};
  bool recoveredByScan = false;
  bool encrypted = false;

  static PdfFile open(Uint8List bytes) {
    final doc = PdfFile._(bytes);
    try {
      doc._readXrefChain();
    } catch (_) {
      doc.xref.clear();
    }
    if (doc.xref.isEmpty || doc._rootDict() == null) {
      doc._scanAllObjects();
      doc.recoveredByScan = true;
    }
    doc.encrypted = doc.trailer['Encrypt'] != null;
    return doc;
  }

  // ---------------------------------------------------------------- xref

  void _readXrefChain() {
    final tailStart = bytes.length - 2048 < 0 ? 0 : bytes.length - 2048;
    final tail = String.fromCharCodes(bytes.sublist(tailStart));
    final i = tail.lastIndexOf('startxref');
    if (i < 0) throw const FormatException('no startxref');
    final m = RegExp(r'startxref\s+(\d+)').firstMatch(tail.substring(i));
    if (m == null) throw const FormatException('bad startxref');
    var offset = int.parse(m.group(1)!);
    final seen = <int>{};
    while (offset > 0 && offset < bytes.length && seen.add(offset)) {
      final next = _readXrefSection(offset);
      if (next == null) break;
      offset = next;
    }
  }

  /// Returns the /Prev offset, 0 when there is none, or null on failure.
  int? _readXrefSection(int offset) {
    final lx = PdfLexer(bytes, offset);
    lx.skipWhitespace();
    final probe = PdfLexer(bytes, lx.pos).parseObject();
    if (probe is PdfKeyword && probe.value == 'xref') {
      return _readClassicXref(lx.pos + 4);
    }
    // Otherwise expect `n g obj << ... >> stream` holding an /XRef stream.
    final obj = _parseIndirectAt(offset);
    if (obj is! PdfStream) return null;
    _readXrefStream(obj);
    for (final k in ['Root', 'Info', 'Encrypt', 'ID', 'Size']) {
      if (obj.dict[k] != null) trailer.putIfAbsent(k, () => obj.dict[k]);
    }
    final hybrid = obj.dict['XRefStm'];
    if (hybrid is int) _readXrefSection(hybrid);
    final prev = obj.dict['Prev'];
    return prev is int ? prev : 0;
  }

  int? _readClassicXref(int start) {
    final lx = PdfLexer(bytes, start);
    while (true) {
      lx.skipWhitespace();
      final save = lx.pos;
      final a = lx.parseObject();
      if (a is PdfKeyword && a.value == 'trailer') {
        final t = lx.parseObject();
        if (t is Map<String, Object?>) {
          t.forEach((k, v) => trailer.putIfAbsent(k, () => v));
          final hybrid = t['XRefStm'];
          if (hybrid is int) _readXrefSection(hybrid);
          final prev = t['Prev'];
          return prev is int ? prev : 0;
        }
        return 0;
      }
      if (a is! int) {
        lx.pos = save;
        return 0;
      }
      final count = lx.parseObject();
      if (count is! int) return 0;
      lx.skipWhitespace();
      for (var i = 0; i < count; i++) {
        final o = lx.parseObject();
        final g = lx.parseObject();
        final ty = lx.parseObject();
        if (o is! int || g is! int || ty is! PdfKeyword) return 0;
        if (ty.value == 'n') {
          xref.putIfAbsent(a + i, () => XrefEntry.offset(o));
        }
      }
    }
  }

  void _readXrefStream(PdfStream s) {
    final data = decodeStream(s);
    final wRaw = resolve(s.dict['W']);
    if (wRaw is! List) return;
    final w = wRaw.map((e) => (resolve(e) as num).toInt()).toList();
    final size = (resolve(s.dict['Size']) as num?)?.toInt() ?? 0;
    final indexRaw = resolve(s.dict['Index']);
    final index = <int>[];
    if (indexRaw is List) {
      for (final e in indexRaw) {
        index.add((resolve(e) as num).toInt());
      }
    } else {
      index
        ..add(0)
        ..add(size);
    }
    final rowLen = w.fold<int>(0, (a, b) => a + b);
    if (rowLen == 0) return;
    var p = 0;
    for (var k = 0; k + 1 < index.length; k += 2) {
      final first = index[k], count = index[k + 1];
      for (var i = 0; i < count; i++) {
        if (p + rowLen > data.length) return;
        final fields = <int>[];
        for (var fi = 0; fi < w.length; fi++) {
          var v = 0;
          for (var b = 0; b < w[fi]; b++) {
            v = (v << 8) | data[p++];
          }
          fields.add(w[fi] == 0 ? (fi == 0 ? 1 : 0) : v);
        }
        final f = fields[0];
        final num0 = first + i;
        if (f == 1) {
          xref.putIfAbsent(num0, () => XrefEntry.offset(fields[1]));
        } else if (f == 2) {
          xref.putIfAbsent(
              num0, () => XrefEntry.compressed(fields[1], fields[2]));
        }
      }
    }
  }

  /// Last-resort recovery: scan the whole file for object headers.
  void _scanAllObjects() {
    final re = RegExp(r'(\d+)\s+(\d+)\s+obj');
    final text = String.fromCharCodes(bytes);
    for (final m in re.allMatches(text)) {
      xref[int.parse(m.group(1)!)] = XrefEntry.offset(m.start);
    }
    _cache.clear();
    if (trailer['Root'] == null) {
      final ti = text.lastIndexOf('trailer');
      if (ti >= 0) {
        final t = PdfLexer(bytes, ti + 7).parseObject();
        if (t is Map<String, Object?>) trailer.addAll(t);
      }
    }
    if (trailer['Root'] == null) {
      for (final e in xref.entries) {
        final o = getObject(e.key);
        final d = o is PdfStream ? o.dict : o;
        if (d is Map<String, Object?>) {
          if (d['Type'] == const PdfName('Catalog')) {
            trailer['Root'] = PdfRef(e.key, 0);
            break;
          }
          if (d['Type'] == const PdfName('XRef') && d['Root'] != null) {
            trailer['Root'] = d['Root'];
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- objects

  Object? _parseIndirectAt(int offset) {
    if (offset < 0 || offset >= bytes.length) return null;
    final lx = PdfLexer(bytes, offset);
    final a = lx.parseObject();
    final b = lx.parseObject();
    final kw = lx.parseObject();
    if (a is! int || b is! int || kw is! PdfKeyword || kw.value != 'obj') {
      return null;
    }
    return _parseObjectBody(lx);
  }

  Object? _parseObjectBody(PdfLexer lx) {
    final value = lx.parseObject();
    lx.skipWhitespace();
    final save = lx.pos;
    final next = lx.parseObject();
    if (next is PdfKeyword &&
        next.value == 'stream' &&
        value is Map<String, Object?>) {
      var p = lx.pos;
      if (p < bytes.length && bytes[p] == 0x0d) p++;
      if (p < bytes.length && bytes[p] == 0x0a) p++;
      final len = resolve(value['Length']);
      var end = (len is num) ? p + len.toInt() : -1;
      if (end < p || end > bytes.length || !_looksLikeEndstream(end)) {
        end = _findEndstream(p);
      }
      return PdfStream(value, Uint8List.sublistView(bytes, p, end));
    }
    lx.pos = save;
    return value;
  }

  bool _looksLikeEndstream(int end) {
    for (var i = end; i < end + 4 && i < bytes.length; i++) {
      if (bytes[i] == 0x65) {
        return String.fromCharCodes(
                bytes.sublist(i, (i + 9).clamp(0, bytes.length))) ==
            'endstream';
      }
      if (!isWhite(bytes[i])) return false;
    }
    return end >= bytes.length - 4;
  }

  int _findEndstream(int from) {
    const needle = [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];
    for (var i = from; i < bytes.length - 9; i++) {
      if (bytes[i] == 0x65) {
        var ok = true;
        for (var k = 1; k < 9; k++) {
          if (bytes[i + k] != needle[k]) {
            ok = false;
            break;
          }
        }
        if (ok) {
          var e = i;
          if (e > from && bytes[e - 1] == 0x0a) e--;
          if (e > from && bytes[e - 1] == 0x0d) e--;
          return e;
        }
      }
    }
    return bytes.length;
  }

  Object? getObject(int number) {
    if (_cache.containsKey(number)) return _cache[number];
    _cache[number] = null; // cycle guard
    final e = xref[number];
    if (e == null) return null;
    Object? out;
    if (e.inObjStm != null) {
      final list = _loadObjStm(e.inObjStm!);
      if (e.indexInStm < list.length) out = list[e.indexInStm];
    } else {
      out = _parseIndirectAt(e.offset);
    }
    _cache[number] = out;
    return out;
  }

  List<Object?> _loadObjStm(int stmNumber) {
    final cached = _objStmCache[stmNumber];
    if (cached != null) return cached;
    _objStmCache[stmNumber] = const [];
    final s = resolve(PdfRef(stmNumber, 0));
    if (s is! PdfStream) return const [];
    final data = decodeStream(s);
    final n = (resolve(s.dict['N']) as num?)?.toInt() ?? 0;
    final first = (resolve(s.dict['First']) as num?)?.toInt() ?? 0;
    final head = PdfLexer(data, 0);
    final offsets = <int>[];
    for (var i = 0; i < n; i++) {
      final num0 = head.parseObject();
      final off = head.parseObject();
      if (num0 is! int || off is! int) break;
      offsets.add(off);
    }
    final out = <Object?>[];
    for (var i = 0; i < offsets.length; i++) {
      final lx = PdfLexer(data, first + offsets[i]);
      out.add(lx.parseObject());
    }
    _objStmCache[stmNumber] = out;
    return out;
  }

  Object? resolve(Object? o) {
    var v = o;
    var guard = 0;
    while (v is PdfRef && guard++ < 32) {
      v = getObject(v.number);
    }
    return v;
  }

  Map<String, Object?>? dict(Object? o) {
    final v = resolve(o);
    if (v is Map<String, Object?>) return v;
    if (v is PdfStream) return v.dict;
    return null;
  }

  // ------------------------------------------------------------- streams

  Uint8List decodeStream(PdfStream s) {
    var data = s.raw;
    final fRaw = resolve(s.dict['Filter']);
    final filters = <String>[];
    if (fRaw is PdfName) {
      filters.add(fRaw.value);
    } else if (fRaw is List) {
      for (final f in fRaw) {
        final r = resolve(f);
        if (r is PdfName) filters.add(r.value);
      }
    }
    final pRaw = resolve(s.dict['DecodeParms'] ?? s.dict['DP']);
    final parms = <Map<String, Object?>?>[];
    if (pRaw is Map<String, Object?>) {
      parms.add(pRaw);
    } else if (pRaw is List) {
      for (final p in pRaw) {
        parms.add(dict(p));
      }
    }
    for (var i = 0; i < filters.length; i++) {
      final f = filters[i];
      final parm = i < parms.length ? parms[i] : null;
      var predictable = false;
      switch (f) {
        case 'FlateDecode':
        case 'Fl':
          data = inflate(data);
          predictable = true;
          break;
        case 'LZWDecode':
        case 'LZW':
          data = lzwDecode(data,
              early: (resolve(parm?['EarlyChange']) as num?)?.toInt() ?? 1);
          predictable = true;
          break;
        case 'ASCII85Decode':
        case 'A85':
          data = ascii85Decode(data);
          break;
        case 'ASCIIHexDecode':
        case 'AHx':
          data = asciiHexDecode(data);
          break;
        case 'RunLengthDecode':
        case 'RL':
          data = runLengthDecode(data);
          break;
        default:
          // DCTDecode / JPXDecode / CCITTFaxDecode stay encoded: the image
          // layer hands DCT bytes straight to the Flutter image codec.
          return data;
      }
      if (predictable && parm != null) {
        data = applyPredictor(
          data,
          predictor: (resolve(parm['Predictor']) as num?)?.toInt() ?? 1,
          colors: (resolve(parm['Colors']) as num?)?.toInt() ?? 1,
          bpc: (resolve(parm['BitsPerComponent']) as num?)?.toInt() ?? 8,
          columns: (resolve(parm['Columns']) as num?)?.toInt() ?? 1,
        );
      }
    }
    return data;
  }

  List<String> streamFilters(PdfStream s) {
    final fRaw = resolve(s.dict['Filter']);
    if (fRaw is PdfName) return [fRaw.value];
    if (fRaw is List) {
      return fRaw
          .map(resolve)
          .whereType<PdfName>()
          .map((e) => e.value)
          .toList();
    }
    return const [];
  }

  // --------------------------------------------------------------- pages

  Map<String, Object?>? _rootDict() => dict(trailer['Root']);

  List<Map<String, Object?>>? _pages;

  /// The page dictionaries in reading order, walked once and then reused.
  ///
  /// The walk is cached because the reader asks for a page on every scroll
  /// frame and the page tree of a long document is thousands of nodes deep.
  List<Map<String, Object?>> get pages => _pages ??= _buildPages();

  /// How many pages this file holds. Zero means nothing readable was found.
  int get pageCount => pages.length;

  List<Map<String, Object?>> _buildPages() {
    final out = <Map<String, Object?>>[];
    final root = _rootDict();
    final tree = dict(root?['Pages']);
    if (tree != null) {
      _walkPages(tree, out, <Object>{}, {});
    }
    if (out.isEmpty) {
      for (final n in xref.keys.toList()..sort()) {
        final o = resolve(PdfRef(n, 0));
        if (o is Map<String, Object?> && o['Type'] == const PdfName('Page')) {
          out.add(o);
        }
      }
    }
    return out;
  }

  static const _inherited = ['Resources', 'MediaBox', 'CropBox', 'Rotate'];

  void _walkPages(Map<String, Object?> node, List<Map<String, Object?>> out,
      Set<Object> seen, Map<String, Object?> inherited) {
    if (!seen.add(node)) return;
    final merged = Map<String, Object?>.from(inherited);
    for (final k in _inherited) {
      if (node[k] != null) merged[k] = node[k];
    }
    final kids = resolve(node['Kids']);
    if (kids is List) {
      for (final k in kids) {
        final kd = dict(k);
        if (kd != null) _walkPages(kd, out, seen, merged);
      }
      return;
    }
    if (node['Type'] == const PdfName('Page') || node['Contents'] != null) {
      final page = Map<String, Object?>.from(node);
      for (final k in _inherited) {
        page.putIfAbsent(k, () => merged[k]);
      }
      out.add(page);
    }
  }

  /// Concatenated, decoded content stream of a page.
  Uint8List pageContent(Map<String, Object?> page) {
    final c = resolve(page['Contents']);
    final chunks = <int>[];
    void add(Object? o) {
      final s = resolve(o);
      if (s is PdfStream) {
        chunks
          ..addAll(decodeStream(s))
          ..add(0x0a);
      }
    }

    if (c is List) {
      for (final e in c) {
        add(e);
      }
    } else {
      add(c);
    }
    return Uint8List.fromList(chunks);
  }

  List<double> mediaBox(Map<String, Object?> page) {
    final mb = resolve(page['MediaBox']);
    if (mb is List && mb.length == 4) {
      return mb.map((e) => ((resolve(e) as num?) ?? 0).toDouble()).toList();
    }
    return const [0, 0, 612, 792];
  }
}

Uint8List lzwDecode(Uint8List data, {int early = 1}) {
  final out = <int>[];
  final table = <List<int>>[];
  void reset() {
    table
      ..clear()
      ..addAll(List.generate(256, (i) => [i]))
      ..add(const <int>[])
      ..add(const <int>[]);
  }

  reset();
  var codeLen = 9, bitBuf = 0, bitCount = 0;
  List<int>? prev;
  for (final b in data) {
    bitBuf = (bitBuf << 8) | b;
    bitCount += 8;
    while (bitCount >= codeLen) {
      final code = (bitBuf >> (bitCount - codeLen)) & ((1 << codeLen) - 1);
      bitCount -= codeLen;
      if (code == 256) {
        reset();
        codeLen = 9;
        prev = null;
        continue;
      }
      if (code == 257) return Uint8List.fromList(out);
      List<int> entry;
      if (code < table.length) {
        entry = table[code];
        if (prev != null) table.add([...prev, entry.first]);
      } else if (prev != null) {
        entry = [...prev, prev.first];
        table.add(entry);
      } else {
        return Uint8List.fromList(out);
      }
      out.addAll(entry);
      prev = entry;
      if (table.length + early - 1 >= (1 << codeLen) && codeLen < 12) codeLen++;
    }
  }
  return Uint8List.fromList(out);
}
