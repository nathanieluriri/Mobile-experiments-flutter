import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/document.dart';

class _Style {
  _Style(this.id);
  final String id;
  String? name;
  String? basedOn;
  int? outlineLvl;
  bool? bold;
  bool? italic;
  bool? underline;
  int? color;
  double? size;
  DocAlign? align;
}

class _NumFmtLvl {
  _NumFmtLvl(this.numFmt, this.lvlText, this.start);
  final String numFmt;
  final String lvlText;
  final int start;
  bool get ordered => numFmt != 'bullet' && numFmt != 'none';
}

/// Reads a .docx into [QuireDocument].
///
/// Word says almost nothing directly: a heading is a style id that inherits
/// from another style id, a bullet is a numbering id that points into a
/// separate part, and a picture is a relationship id three elements deep. Most
/// of this class is resolving those indirections so the model can stay plain.
///
/// Throws [ArchiveException] when the bytes are not a readable zip, and
/// [FormatException] when they are a zip without a Word document inside. Both
/// are caught at the loader boundary and become a designed state.
class DocxParser {
  DocxParser(this.bytes);
  final Uint8List bytes;

  late Archive _zip;
  final Map<String, _Style> _styles = {};
  final Map<String, String> _rels = {}; // rId -> target
  final Map<String, String> _relTypes = {}; // rId -> type suffix
  final Map<String, Map<int, _NumFmtLvl>> _numbering = {}; // numId -> ilvl
  final Map<String, List<int>> _counters = {}; // numId -> count per level
  final Map<String, Uint8List> _assets = {};

  static String _ln(XmlElement e) => e.name.local;

  Iterable<XmlElement> _kids(XmlElement e, String local) =>
      e.childElements.where((c) => _ln(c) == local);

  XmlElement? _kid(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (_ln(c) == local) return c;
    }
    return null;
  }

  /// Attribute lookup ignoring namespace prefix.
  static String? _at(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  String? _text(String path) {
    final f = _zip.files.firstWhere(
      (f) => f.name == path,
      orElse: () => ArchiveFile('', 0, const <int>[]),
    );
    if (f.name.isEmpty) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  /// Parses the whole document in one pass over the body.
  QuireDocument parse({String title = 'Document'}) {
    _zip = ZipDecoder().decodeBytes(bytes);
    _loadStyles();
    _loadRels();
    _loadNumbering();
    _loadMedia();

    final xml = _text('word/document.xml');
    if (xml == null) throw const FormatException('no word/document.xml');
    final doc = XmlDocument.parse(xml);
    final body = doc.rootElement.childElements.firstWhere(
      (e) => _ln(e) == 'body',
    );

    final blocks = <DocBlock>[];
    for (final el in body.childElements) {
      switch (_ln(el)) {
        case 'p':
          final b = _paragraph(el);
          if (b != null) blocks.add(b);
        case 'tbl':
          blocks.add(_table(el));
        case 'sdt':
          // content controls wrap real content
          final c = _kid(el, 'sdtContent');
          if (c != null) {
            for (final inner in c.childElements) {
              if (_ln(inner) == 'p') {
                final b = _paragraph(inner);
                if (b != null) blocks.add(b);
              } else if (_ln(inner) == 'tbl') {
                blocks.add(_table(inner));
              }
            }
          }
      }
    }

    final outline = <OutlineEntry>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b is HeadingBlock) outline.add(OutlineEntry(b.text, b.level, 0, i));
    }

    return QuireDocument(
      title: title,
      sections: [DocSection(title, blocks)],
      assets: _assets,
      sourceFormat: 'docx',
      outline: outline,
    );
  }

  void _loadMedia() {
    for (final f in _zip.files) {
      if (f.name.startsWith('word/media/') && f.isFile) {
        _assets[f.name] = Uint8List.fromList(f.content as List<int>);
      }
    }
  }

  void _loadRels() {
    final xml = _text('word/_rels/document.xml.rels');
    if (xml == null) return;
    for (final r in XmlDocument.parse(xml).rootElement.childElements) {
      final id = _at(r, 'Id');
      final target = _at(r, 'Target');
      final type = _at(r, 'Type') ?? '';
      if (id == null || target == null) continue;
      _rels[id] = target;
      _relTypes[id] = type.split('/').last;
    }
  }

  void _loadStyles() {
    final xml = _text('word/styles.xml');
    if (xml == null) return;
    for (final s in XmlDocument.parse(xml).rootElement.childElements) {
      if (_ln(s) != 'style') continue;
      final id = _at(s, 'styleId');
      if (id == null) continue;
      final st = _Style(id);
      st.name = _kid(s, 'name') == null ? null : _at(_kid(s, 'name')!, 'val');
      st.basedOn =
          _kid(s, 'basedOn') == null ? null : _at(_kid(s, 'basedOn')!, 'val');
      final pPr = _kid(s, 'pPr');
      if (pPr != null) {
        final ol = _kid(pPr, 'outlineLvl');
        if (ol != null) st.outlineLvl = int.tryParse(_at(ol, 'val') ?? '');
        st.align = _alignOf(pPr);
      }
      final rPr = _kid(s, 'rPr');
      if (rPr != null) {
        st.bold = _onOff(rPr, 'b');
        st.italic = _onOff(rPr, 'i');
        st.underline = _kid(rPr, 'u') != null &&
            (_at(_kid(rPr, 'u')!, 'val') ?? 'single') != 'none';
        final c = _kid(rPr, 'color');
        if (c != null) st.color = _hex(_at(c, 'val'));
        final sz = _kid(rPr, 'sz');
        if (sz != null) {
          final v = double.tryParse(_at(sz, 'val') ?? '');
          if (v != null) st.size = v / 2;
        }
      }
      _styles[id] = st;
    }
  }

  void _loadNumbering() {
    final xml = _text('word/numbering.xml');
    if (xml == null) return;
    final root = XmlDocument.parse(xml).rootElement;
    final abstracts = <String, Map<int, _NumFmtLvl>>{};
    for (final an in root.childElements.where((e) => _ln(e) == 'abstractNum')) {
      final id = _at(an, 'abstractNumId');
      if (id == null) continue;
      final lvls = <int, _NumFmtLvl>{};
      for (final l in _kids(an, 'lvl')) {
        final ilvl = int.tryParse(_at(l, 'ilvl') ?? '0') ?? 0;
        final fmt = _kid(l, 'numFmt');
        final txt = _kid(l, 'lvlText');
        final start = _kid(l, 'start');
        lvls[ilvl] = _NumFmtLvl(
          fmt == null ? 'bullet' : (_at(fmt, 'val') ?? 'bullet'),
          txt == null ? '•' : (_at(txt, 'val') ?? '•'),
          start == null ? 1 : (int.tryParse(_at(start, 'val') ?? '1') ?? 1),
        );
      }
      abstracts[id] = lvls;
    }
    for (final n in root.childElements.where((e) => _ln(e) == 'num')) {
      final numId = _at(n, 'numId');
      final ab = _kid(n, 'abstractNumId');
      if (numId == null || ab == null) continue;
      final target = abstracts[_at(ab, 'val')];
      if (target != null) _numbering[numId] = target;
    }
  }

  static int? _hex(String? v) {
    if (v == null || v.length != 6 || v.toLowerCase() == 'auto') return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : 0xFF000000 | n;
  }

  static bool _onOff(XmlElement rPr, String tag) {
    for (final c in rPr.childElements) {
      if (_ln(c) == tag) {
        final v = _at(c, 'val');
        return v == null || v == '1' || v == 'true' || v == 'on';
      }
    }
    return false;
  }

  DocAlign? _alignOf(XmlElement pPr) {
    final jc = _kid(pPr, 'jc');
    if (jc == null) return null;
    return switch (_at(jc, 'val')) {
      'center' => DocAlign.center,
      'right' || 'end' => DocAlign.end,
      'both' || 'distribute' => DocAlign.justify,
      _ => DocAlign.start,
    };
  }

  /// Resolve a paragraph style id to a heading level, walking basedOn.
  int? _headingLevel(String? styleId) {
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final st = _styles[id];
      if (st == null) break;
      if (st.outlineLvl != null && st.outlineLvl! < 9) return st.outlineLvl! + 1;
      final name = (st.name ?? '').toLowerCase();
      final m = RegExp(r'^heading\s*(\d)').firstMatch(name);
      if (m != null) return int.parse(m.group(1)!);
      id = st.basedOn;
    }
    final m = RegExp(r'^Heading(\d)$').firstMatch(styleId ?? '');
    if (m != null) return int.parse(m.group(1)!);
    return null;
  }

  DocBlock? _paragraph(XmlElement p) {
    final pPr = _kid(p, 'pPr');
    String? styleId;
    DocAlign align = DocAlign.start;
    int indent = 0;
    String? numId;
    int ilvl = 0;
    if (pPr != null) {
      final ps = _kid(pPr, 'pStyle');
      if (ps != null) styleId = _at(ps, 'val');
      align = _alignOf(pPr) ?? DocAlign.start;
      final ind = _kid(pPr, 'ind');
      if (ind != null) {
        final left = int.tryParse(_at(ind, 'left') ?? _at(ind, 'start') ?? '');
        if (left != null) indent = (left / 720).round();
      }
      final np = _kid(pPr, 'numPr');
      if (np != null) {
        final n = _kid(np, 'numId');
        final l = _kid(np, 'ilvl');
        numId = n == null ? null : _at(n, 'val');
        ilvl = l == null ? 0 : (int.tryParse(_at(l, 'val') ?? '0') ?? 0);
      }
    }

    final spans = <DocSpan>[];
    final images = <ImageBlock>[];
    _collectInline(p, spans, images, null);

    if (spans.isEmpty && images.isNotEmpty) return images.first;
    if (spans.isEmpty && images.isEmpty) {
      return const ParagraphBlock([DocSpan('')]);
    }

    if (numId != null && numId != '0') {
      final lvl = _numbering[numId]?[ilvl];
      return ListItemBlock(
        spans,
        level: ilvl,
        ordered: lvl?.ordered ?? false,
        marker: _markerFor(numId, ilvl, lvl),
      );
    }

    final level = _headingLevel(styleId);
    if (level != null) return HeadingBlock(level, spans);

    final styleName = (_styles[styleId]?.name ?? '').toLowerCase();
    final quote = styleName.contains('quote');
    return ParagraphBlock(spans,
        align: align, indent: indent, quote: quote, styleId: styleId);
  }


  /// The glyph or number this item actually shows.
  ///
  /// Word stores a pattern, not a marker: `%1.` means "the count at level one,
  /// then a full stop", and a bullet is a code point in a symbol font's
  /// private use area. Neither is readable as it stands, so both are resolved
  /// here rather than left for a renderer to guess at.
  String? _markerFor(String numId, int ilvl, _NumFmtLvl? lvl) {
    if (lvl == null) return null;
    if (!lvl.ordered) return _bulletGlyph(lvl.lvlText);

    final levels = _numbering[numId] ?? const <int, _NumFmtLvl>{};
    final counters = _counters.putIfAbsent(numId, () => <int>[]);
    while (counters.length <= ilvl) {
      counters.add((levels[counters.length]?.start ?? 1) - 1);
    }
    counters[ilvl]++;
    // A deeper list restarts every time its parent advances, which is what
    // makes a, b, c begin again under each numbered step.
    for (var deeper = ilvl + 1; deeper < counters.length; deeper++) {
      counters[deeper] = (levels[deeper]?.start ?? 1) - 1;
    }

    var text = lvl.lvlText;
    for (var level = counters.length; level >= 1; level--) {
      text = text.replaceAll(
        '%$level',
        _numberAs(counters[level - 1], levels[level - 1]?.numFmt ?? 'decimal'),
      );
    }
    return text;
  }

  /// Symbol and Wingdings bullets arrive as private use code points that no
  /// text font can draw. Each is mapped to the Unicode glyph it stands for, so
  /// a list reads as a list instead of as a row of empty boxes.
  static String _bulletGlyph(String text) {
    if (text.isEmpty) return '•';
    if (text == 'o') return '◦';
    const map = <int, String>{
      0xF0B7: '•',
      0xF0A7: '▪',
      0xF0A8: '▫',
      0xF06E: '▪',
      0xF0FC: '✓',
      0xF0D8: '➤',
      0x00B7: '•',
    };
    final mapped = map[text.codeUnitAt(0)];
    return mapped ?? text;
  }

  static String _numberAs(int value, String numFmt) => switch (numFmt) {
        'decimal' => '$value',
        'decimalZero' => value.toString().padLeft(2, '0'),
        'lowerLetter' => _letters(value).toLowerCase(),
        'upperLetter' => _letters(value),
        'lowerRoman' => _roman(value).toLowerCase(),
        'upperRoman' => _roman(value),
        _ => '$value',
      };

  static String _letters(int value) {
    if (value < 1) return '';
    var n = value;
    final out = <int>[];
    while (n > 0) {
      final rem = (n - 1) % 26;
      out.insert(0, 65 + rem);
      n = (n - 1) ~/ 26;
    }
    return String.fromCharCodes(out);
  }

  static String _roman(int value) {
    if (value < 1 || value > 3999) return '$value';
    const numerals = <int, String>{
      1000: 'M', 900: 'CM', 500: 'D', 400: 'CD', 100: 'C', 90: 'XC',
      50: 'L', 40: 'XL', 10: 'X', 9: 'IX', 5: 'V', 4: 'IV', 1: 'I',
    };
    var n = value;
    final out = StringBuffer();
    for (final entry in numerals.entries) {
      while (n >= entry.key) {
        out.write(entry.value);
        n -= entry.key;
      }
    }
    return out.toString();
  }

  /// Walks runs, hyperlinks, smartTags, bookmarks, fields and drawings.
  void _collectInline(
    XmlElement node,
    List<DocSpan> spans,
    List<ImageBlock> images,
    String? href,
  ) {
    for (final el in node.childElements) {
      switch (_ln(el)) {
        case 'r':
          _run(el, spans, images, href);
        case 'hyperlink':
          final rid = _at(el, 'id');
          final anchor = _at(el, 'anchor');
          final target = rid != null ? _rels[rid] : null;
          _collectInline(
              el, spans, images, target ?? (anchor == null ? null : '#$anchor'));
        case 'smartTag':
        case 'ins':
        case 'bookmarkStart':
          _collectInline(el, spans, images, href);
        case 'del':
          break; // tracked deletion, skip
        case 'fldSimple':
          _collectInline(el, spans, images, href);
      }
    }
  }

  void _run(
    XmlElement r,
    List<DocSpan> spans,
    List<ImageBlock> images,
    String? href,
  ) {
    final rPr = _kid(r, 'rPr');
    var bold = false,
        italic = false,
        underline = false,
        strike = false,
        mono = false;
    int? color;
    int? highlight;
    double? size;
    var script = 0;
    if (rPr != null) {
      bold = _onOff(rPr, 'b');
      italic = _onOff(rPr, 'i');
      strike = _onOff(rPr, 'strike') || _onOff(rPr, 'dstrike');
      final u = _kid(rPr, 'u');
      underline = u != null && (_at(u, 'val') ?? 'single') != 'none';
      final c = _kid(rPr, 'color');
      if (c != null) color = _hex(_at(c, 'val'));
      final h = _kid(rPr, 'highlight');
      if (h != null) highlight = _namedColor(_at(h, 'val'));
      final sz = _kid(rPr, 'sz');
      if (sz != null) {
        final v = double.tryParse(_at(sz, 'val') ?? '');
        if (v != null) size = v / 2;
      }
      final va = _kid(rPr, 'vertAlign');
      if (va != null) {
        script = switch (_at(va, 'val')) {
          'superscript' => 1,
          'subscript' => -1,
          _ => 0,
        };
      }
      final rStyle = _kid(rPr, 'rStyle');
      if (rStyle != null) {
        final st = _styles[_at(rStyle, 'val')];
        if (st != null) {
          bold = bold || (st.bold ?? false);
          italic = italic || (st.italic ?? false);
          underline = underline || (st.underline ?? false);
          color ??= st.color;
          size ??= st.size;
          final n = (st.name ?? '').toLowerCase();
          if (n.contains('code') || n.contains('html')) mono = true;
        }
      }
      final fonts = _kid(rPr, 'rFonts');
      if (fonts != null) {
        final ascii = (_at(fonts, 'ascii') ?? '').toLowerCase();
        if (ascii.contains('consol') ||
            ascii.contains('courier') ||
            ascii.contains('mono')) {
          mono = true;
        }
      }
    }

    DocSpan mk(String t) => DocSpan(
          t,
          bold: bold,
          italic: italic,
          underline: underline,
          strike: strike,
          mono: mono,
          color: color,
          highlight: highlight,
          fontSize: size,
          href: href,
          script: script,
        );

    for (final c in r.childElements) {
      switch (_ln(c)) {
        case 't':
          spans.add(mk(c.innerText));
        case 'br':
          spans.add(mk('\n'));
        case 'cr':
          spans.add(mk('\n'));
        case 'tab':
          spans.add(mk('\t'));
        case 'noBreakHyphen':
          spans.add(mk('‑'));
        case 'sym':
          final ch = _at(c, 'char');
          if (ch != null) {
            final code = int.tryParse(ch, radix: 16);
            if (code != null) spans.add(mk(String.fromCharCode(code & 0xFF)));
          }
        case 'drawing':
        case 'pict':
        case 'object':
          final img = _drawing(c);
          if (img != null) images.add(img);
      }
    }
  }

  ImageBlock? _drawing(XmlElement d) {
    String? rid;
    String? alt;
    double? w, h;
    for (final e in d.descendantElements) {
      final n = _ln(e);
      if (n == 'blip' || n == 'imagedata') {
        rid ??= _at(e, 'embed') ?? _at(e, 'id') ?? _at(e, 'link');
      } else if (n == 'extent') {
        final cx = double.tryParse(_at(e, 'cx') ?? '');
        final cy = double.tryParse(_at(e, 'cy') ?? '');
        if (cx != null) w = cx / 12700.0; // EMU -> points
        if (cy != null) h = cy / 12700.0;
      } else if (n == 'docPr') {
        alt = _at(e, 'descr') ?? _at(e, 'name');
      }
    }
    if (rid == null) return null;
    final target = _rels[rid];
    if (target == null) return null;
    final key = target.startsWith('/')
        ? target.substring(1)
        : 'word/${target.replaceAll('../', '')}';
    if (!_assets.containsKey(key)) return null;
    return ImageBlock(key, width: w, height: h, alt: alt);
  }

  static int? _namedColor(String? v) => switch (v) {
        'yellow' => 0xFFFFFF00,
        'green' => 0xFF00FF00,
        'cyan' => 0xFF00FFFF,
        'magenta' => 0xFFFF00FF,
        'red' => 0xFFFF0000,
        'darkYellow' => 0xFF808000,
        'lightGray' => 0xFFD3D3D3,
        _ => null,
      };

  TableBlock _table(XmlElement tbl) {
    final columns = <DocColumn>[];
    final grid = _kid(tbl, 'tblGrid');
    if (grid != null) {
      for (final g in _kids(grid, 'gridCol')) {
        final w = double.tryParse(_at(g, 'w') ?? '');
        columns.add(DocColumn(width: w == null ? null : w / 20.0));
      }
    }
    final rows = <DocRow>[];
    for (final tr in _kids(tbl, 'tr')) {
      final trPr = _kid(tr, 'trPr');
      final header = trPr != null && _kid(trPr, 'tblHeader') != null;
      double? height;
      if (trPr != null) {
        final h = _kid(trPr, 'trHeight');
        final v = h == null ? null : double.tryParse(_at(h, 'val') ?? '');
        if (v != null) height = v / 20.0;
      }
      final cells = <DocCell>[];
      for (final tc in _kids(tr, 'tc')) {
        final tcPr = _kid(tc, 'tcPr');
        var colSpan = 1;
        var merged = false;
        int? bg;
        if (tcPr != null) {
          final gs = _kid(tcPr, 'gridSpan');
          if (gs != null) colSpan = int.tryParse(_at(gs, 'val') ?? '1') ?? 1;
          final vm = _kid(tcPr, 'vMerge');
          if (vm != null && (_at(vm, 'val') ?? 'continue') != 'restart') {
            merged = true;
          }
          final shd = _kid(tcPr, 'shd');
          if (shd != null) bg = _hex(_at(shd, 'fill'));
        }
        final blocks = <DocBlock>[];
        for (final child in tc.childElements) {
          if (_ln(child) == 'p') {
            final b = _paragraph(child);
            if (b != null) blocks.add(b);
          } else if (_ln(child) == 'tbl') {
            blocks.add(_table(child));
          }
        }
        cells.add(DocCell(blocks,
            colSpan: colSpan, merged: merged, background: bg));
      }
      rows.add(DocRow(cells, header: header, height: height));
    }
    // Resolve vertical merges into rowSpan on the anchor cell.
    final resolved = <DocRow>[];
    for (var r = 0; r < rows.length; r++) {
      final cells = <DocCell>[];
      for (var c = 0; c < rows[r].cells.length; c++) {
        final cell = rows[r].cells[c];
        if (cell.merged) {
          cells.add(cell);
          continue;
        }
        var span = 1;
        for (var k = r + 1; k < rows.length; k++) {
          if (c < rows[k].cells.length && rows[k].cells[c].merged) {
            span++;
          } else {
            break;
          }
        }
        cells.add(DocCell(cell.blocks,
            colSpan: cell.colSpan,
            rowSpan: span,
            background: cell.background));
      }
      resolved.add(DocRow(cells, header: rows[r].header, height: rows[r].height));
    }
    return TableBlock(resolved,
        columns: columns, frozenRows: resolved.isNotEmpty && resolved.first.header ? 1 : 0);
  }
}
