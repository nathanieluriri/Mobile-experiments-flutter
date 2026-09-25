import 'dart:typed_data';
import 'crypt.dart';
import 'filters.dart';
import 'lexer.dart';
import 'objects.dart';

/// Thrown when the file is encrypted and the password did not open it.
///
/// [wrongPassword] is false when no password was supplied at all, and true
/// when one was supplied and rejected, so the reader can tell "locked" from
/// "that is not the password" and ask the right question.
class PdfLocked implements Exception {
  const PdfLocked({required this.wrongPassword, required this.cipher});

  final bool wrongPassword;

  /// [kCipherRc4] when this reader can decrypt the file given the right
  /// password, or the cipher's own name when it cannot, for example `AESV2`.
  final String cipher;

  @override
  String toString() =>
      'PdfLocked(cipher: $cipher, wrongPassword: $wrongPassword)';
}

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
/// [open] recovers rather than refuses: a file whose xref is unreachable or
/// whose catalogue is missing falls through to [_scanAllObjects], which is why
/// a damaged download still opens to its real pages instead of an error sheet.
///
/// Everything a file decides the depth of is capped at [kMaxPdfNesting]: the
/// nesting of its objects, its page tree and its chain of cross reference
/// sections. An object nested past it reads as absent rather than as a stack
/// overflow.
class PdfFile {
  PdfFile._(this.bytes);
  final Uint8List bytes;

  final Map<int, XrefEntry> xref = {};
  final Map<int, Object?> _cache = {};
  final Map<int, List<Object?>> _objStmCache = {};
  Map<String, Object?> trailer = {};
  bool recoveredByScan = false;

  /// Where the file's own last cross reference section starts, or 0 when it
  /// was never found, which is what an update has to point back at.
  int startxref = 0;

  /// True when that section is a cross reference stream rather than a table,
  /// which decides what kind of section an update may add after it.
  bool xrefIsStream = false;

  /// The reference each entry of [pages] was reached through, or null for a
  /// page found by scanning that has no reference the writer can trust.
  List<PdfRef?> get pageRefs {
    pages;
    return _pageRefs;
  }

  final List<PdfRef?> _pageRefs = <PdfRef?>[];

  /// [data] as it has to be written into object [number], which is to say
  /// encrypted under that object's key when the file is encrypted and left
  /// alone when it is not. RC4 is its own inverse, so the one routine that
  /// reads a string is the one that writes it.
  Uint8List encryptForObject(Uint8List data, int number, int generation) {
    final crypt = _crypt;
    if (crypt == null) return data;
    return crypt.decrypt(data, number, generation);
  }

  /// The program that wrote the file, from its /Info, or '' when it does not
  /// say. Most reading faults belong to one producer, so this is the first
  /// thing to know about a page that reads badly.
  String get producer {
    final value = resolve(dict(trailer['Info'])?['Producer']);
    if (value is! PdfString) return '';
    final b = value.bytes;
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < b.length; i += 2) {
        units.add((b[i] << 8) | b[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    return value.asLatin1;
  }

  /// True when the trailer carries an /Encrypt dictionary, whether or not the
  /// file went on to open.
  bool encrypted = false;

  PdfCrypt? _crypt;
  int? _encryptNumber;

  /// The security handler this file was opened with, or null when it carries
  /// no encryption. It is what the revision and the cipher are read from.
  PdfSecurity? get security => _crypt?.security;

  /// True when the file is encrypted and no key was found for it. [open]
  /// throws rather than returning such a file, so this is false on every
  /// instance a caller ever holds. It stays here because the fallback ladder
  /// asks the question and an expression that answers by construction is
  /// better than one that answers by luck.
  bool get locked => encrypted && _crypt == null;

  /// Opens [bytes]. Throws [PdfLocked] when the file is encrypted and neither
  /// the empty password nor [password] opens it.
  ///
  /// The empty password is always tried first. Most protected files in the
  /// wild carry only an owner password, restricting printing or copying, and
  /// their user password is empty, so a conforming reader opens them with no
  /// prompt at all. Refusing those would be refusing files we can simply read.
  static PdfFile open(Uint8List bytes, {String password = ''}) {
    final doc = _read(bytes);
    if (doc.encrypted) doc._unlock(password);
    return doc;
  }

  /// The security handler of [bytes] without trying any password, or null when
  /// the file carries no encryption.
  ///
  /// A file this reader cannot open still has something true to say about
  /// itself: which handler locked it, and at which revision. Reading that
  /// costs the xref chain alone and no object at all.
  static PdfSecurity? securityOf(Uint8List bytes) {
    final doc = _read(bytes);
    if (!doc.encrypted) return null;
    final dictionary = doc.dict(doc.trailer['Encrypt']);
    if (dictionary == null) return null;
    return PdfSecurity.read(dictionary, doc.resolve);
  }

  /// The xref chain and the trailer, with nothing decrypted yet.
  static PdfFile _read(Uint8List bytes) {
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

  // ------------------------------------------------------------ decryption

  /// Finds the file key, or throws [PdfLocked] saying which of the two things
  /// went wrong: a cipher we do not implement, or a password we do not have.
  void _unlock(String password) {
    final entry = trailer['Encrypt'];
    if (entry is PdfRef) _encryptNumber = entry.number;
    final dictionary = dict(entry);
    if (dictionary == null) {
      throw const PdfLocked(wrongPassword: false, cipher: 'unknown');
    }

    final security = PdfSecurity.read(dictionary, resolve);
    if (security.cipher != kCipherRc4) {
      // Reporting the cipher by name is the honest answer. Attempting AES with
      // an RC4 handler would produce a page of noise and call it a document.
      throw PdfLocked(wrongPassword: false, cipher: security.cipher);
    }

    final id = _firstId();
    final crypt =
        _tryPassword(security, id, '') ??
        (password.isEmpty ? null : _tryPassword(security, id, password));
    if (crypt == null) {
      throw PdfLocked(
        wrongPassword: password.isNotEmpty,
        cipher: security.cipher,
      );
    }

    _crypt = crypt;
    // Everything parsed while the key was still unknown was parsed in cipher
    // text, including whatever the catalogue walk touched, so the caches start
    // again now that objects can be read.
    _cache.clear();
    _objStmCache.clear();
    _pages = null;
  }

  PdfCrypt? _tryPassword(PdfSecurity security, Uint8List id, String password) {
    final bytes = _passwordBytes(password);
    return PdfCrypt.unlock(security, id, padPassword(bytes)) ??
        PdfCrypt.unlockAsOwner(security, id, bytes);
  }

  /// A password is bytes, not text: the handler pads Latin-1 code units, so a
  /// character past 255 is taken a byte at a time rather than silently
  /// truncated to something that would never match.
  static Uint8List _passwordBytes(String password) {
    final out = Uint8List(password.length);
    for (var i = 0; i < password.length; i++) {
      out[i] = password.codeUnitAt(i) & 0xff;
    }
    return out;
  }

  /// The first element of the trailer's /ID array, which Algorithm 2 mixes
  /// into the key. It is not itself encrypted.
  Uint8List _firstId() {
    final id = resolve(trailer['ID']);
    if (id is List && id.isNotEmpty) {
      final first = resolve(id.first);
      if (first is PdfString) return first.bytes;
    }
    return Uint8List(0);
  }

  /// Replaces every string, and a stream's bytes, with their clear text.
  ///
  /// Two objects are never decrypted: the /Encrypt dictionary, which is stored
  /// in clear by definition, and an /XRef stream, which has to be readable
  /// before a key exists at all. Decrypting either makes a sound file look
  /// corrupt, which is the worst of the failures because it points nowhere.
  Object? _decrypt(Object? object, int number, int generation) {
    final crypt = _crypt;
    if (crypt == null || number == _encryptNumber) return object;

    if (object is PdfStream) {
      final dictionary = _decryptStrings(object.dict, crypt, number, generation)
          as Map<String, Object?>;
      if (!crypt.security.encryptStreams ||
          dictionary['Type'] == const PdfName('XRef')) {
        return PdfStream(dictionary, object.raw);
      }
      return PdfStream(
        dictionary,
        crypt.decrypt(object.raw, number, generation),
      );
    }
    return _decryptStrings(object, crypt, number, generation);
  }

  Object? _decryptStrings(
    Object? value,
    PdfCrypt crypt,
    int number,
    int generation,
  ) {
    if (!crypt.security.encryptStrings) return value;
    if (value is PdfString) {
      return PdfString(crypt.decrypt(value.bytes, number, generation));
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        value[i] = _decryptStrings(value[i], crypt, number, generation);
      }
      return value;
    }
    if (value is Map<String, Object?>) {
      for (final key in value.keys.toList()) {
        value[key] = _decryptStrings(value[key], crypt, number, generation);
      }
      return value;
    }
    return value;
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
    startxref = offset;
    if (offset > 0 && offset < bytes.length) {
      final probe = PdfLexer(bytes, offset)..skipWhitespace();
      final word = PdfLexer(bytes, probe.pos).parseObject();
      xrefIsStream = !(word is PdfKeyword && word.value == 'xref');
    }
    final seen = _xrefSeen..clear();
    while (offset > 0 && offset < bytes.length && seen.add(offset)) {
      final next = _readXrefSection(offset);
      if (next == null) break;
      offset = next;
    }
  }

  /// Every section read so far, shared by the /Prev chain and the /XRefStm
  /// a hybrid trailer points at, so neither can lead back to a section
  /// already read. A stream whose /XRefStm named itself recursed until the
  /// stack ran out.
  final Set<int> _xrefSeen = <int>{};

  void _readHybrid(Object? at) {
    if (at is int && _xrefSeen.add(at)) _readXrefSection(at);
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
    _readHybrid(obj.dict['XRefStm']);
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
          _readHybrid(t['XRefStm']);
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
    return _decrypt(_parseObjectBody(lx), a, b);
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
    try {
      if (e.inObjStm != null) {
        final list = _loadObjStm(e.inObjStm!);
        if (e.indexInStm < list.length) out = list[e.indexInStm];
      } else {
        out = _parseIndirectAt(e.offset);
      }
    } on PdfTooDeep {
      out = null;
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
      try {
        out.add(lx.parseObject());
      } on PdfTooDeep {
        out.add(null);
      }
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
    _pageRefs.clear();
    final root = _rootDict();
    final tree = dict(root?['Pages']);
    if (tree != null) {
      _walkPages(tree, null, out, <Object>{}, {}, 0);
    }
    if (out.isEmpty) {
      _pageRefs.clear();
      for (final n in xref.keys.toList()..sort()) {
        final o = resolve(PdfRef(n, 0));
        if (o is Map<String, Object?> && o['Type'] == const PdfName('Page')) {
          out.add(o);
          _pageRefs.add(PdfRef(n, 0));
        }
      }
    }
    return out;
  }

  static const _inherited = ['Resources', 'MediaBox', 'CropBox', 'Rotate'];

  void _walkPages(Map<String, Object?> node, PdfRef? ref,
      List<Map<String, Object?>> out, Set<Object> seen,
      Map<String, Object?> inherited, int depth) {
    // The seen set stops a cycle but not a chain: a linear run of /Pages
    // nodes has no cycle and ran the stack out sixty thousand deep.
    if (depth > kMaxPdfNesting || !seen.add(node)) return;
    final merged = Map<String, Object?>.from(inherited);
    for (final k in _inherited) {
      if (node[k] != null) merged[k] = node[k];
    }
    final kids = resolve(node['Kids']);
    if (kids is List) {
      for (final k in kids) {
        final kd = dict(k);
        if (kd != null) {
          _walkPages(kd, k is PdfRef ? k : null, out, seen, merged, depth + 1);
        }
      }
      return;
    }
    if (node['Type'] == const PdfName('Page') || node['Contents'] != null) {
      final page = Map<String, Object?>.from(node);
      for (final k in _inherited) {
        page.putIfAbsent(k, () => merged[k]);
      }
      out.add(page);
      _pageRefs.add(ref);
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
  final limit = decodeLimit(data.length);
  final out = BytesBuilder(copy: false);
  var written = 0;
  final table = <Uint8List>[];
  void reset() {
    table
      ..clear()
      ..addAll(List.generate(256, (i) => Uint8List.fromList([i])))
      ..add(Uint8List(0))
      ..add(Uint8List(0));
  }

  Uint8List extended(Uint8List head, int last) =>
      Uint8List(head.length + 1)
        ..setRange(0, head.length, head)
        ..[head.length] = last;

  reset();
  var codeLen = 9, bitBuf = 0, bitCount = 0;
  Uint8List? prev;
  for (final b in data) {
    bitBuf = ((bitBuf << 8) | b) & 0xFFFFFF;
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
      if (code == 257) return out.takeBytes();
      Uint8List entry;
      // A full table takes no more entries until the next clear code. Left
      // to grow, a stream that never clears adds a string up to four
      // thousand bytes long for every code it reads.
      final full = table.length >= 4096;
      if (code < table.length) {
        entry = table[code];
        if (prev != null && !full) table.add(extended(prev, entry.first));
      } else if (prev != null && prev.isNotEmpty) {
        entry = extended(prev, prev.first);
        if (!full) table.add(entry);
      } else {
        return out.takeBytes();
      }
      written += entry.length;
      if (written > limit) throw const PdfStreamTooLarge();
      out.add(entry);
      prev = entry;
      if (table.length + early - 1 >= (1 << codeLen) && codeLen < 12) codeLen++;
    }
  }
  return out.takeBytes();
}
