import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'ooxml_patch.dart';

/// One piece of a line: text with its look, or something kept whole.
typedef DeltaOp = Map<String, Object?>;

const String kWordNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const String kRelNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// The embed a table, a section break or anything else quire keeps whole
/// takes in the editor, and the one something inline takes.
const String kBlockEmbed = 'quire-block';
const String kInlineEmbed = 'quire-inline';

/// A soft line break inside a paragraph, which Word writes as `w:br`.
const String kSoftBreak = ' ';

/// The look of a run of text, resolved through the document's styles.
class RunLook {
  const RunLook({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.background,
    this.size = 10,
    this.font = 'Times New Roman',
    this.script = 0,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// 0xRRGGBB, or null for the page's ink.
  final int? color;
  final int? background;

  /// Points.
  final double size;
  final String font;

  /// 1 superscript, -1 subscript.
  final int script;

  /// What a piece of text in this look needs on top of a line drawn in
  /// [line], as attributes on the editor's text.
  Map<String, Object?> over(RunLook line) => <String, Object?>{
        if (bold != line.bold) 'bold': bold,
        if (italic != line.italic) 'italic': italic,
        if (underline != line.underline) 'underline': underline,
        if (strike != line.strike) 'strike': strike,
        if ((color ?? 0) != (line.color ?? 0)) 'color': _hexOf(color ?? 0),
        if (background != null && background != line.background) 'background': _hexOf(background!),
        if (size != line.size) 'size': _sizeText(size),
        if (font != line.font) 'font': font,
        if (script == 1 && line.script != 1) 'script': 'super',
        if (script == -1 && line.script != -1) 'script': 'sub',
      };

  /// The look the editor draws text with [attributes] in, on a line of this
  /// look.
  RunLook withAttributes(Map<String, Object?> attributes) => RunLook(
        bold: _flag(attributes['bold'], bold),
        italic: _flag(attributes['italic'], italic),
        underline: _flag(attributes['underline'], underline),
        strike: _flag(attributes['strike'], strike),
        color: attributes['color'] == null ? color : _rgbOf(attributes['color']) ?? color,
        background: _rgbOf(attributes['background']) ?? background,
        size: _sizeOf(attributes['size']) ?? size,
        font: attributes['font'] as String? ?? font,
        script: switch (attributes['script']) {
          'super' => 1,
          'sub' => -1,
          _ => script,
        },
      );

  RunLook copyWith({bool? bold, double? size}) => RunLook(
        bold: bold ?? this.bold,
        italic: italic,
        underline: underline,
        strike: strike,
        color: color,
        background: background,
        size: size ?? this.size,
        font: font,
        script: script,
      );
}

/// How a paragraph style sets its lines: the look of its text, the space
/// around it, its line spacing, its indents and a rule down its left side.
class ParagraphLook {
  const ParagraphLook(
    this.run, {
    this.before = 0,
    this.after = 0,
    this.line = 1,
    this.left = 0,
    this.right = 0,
    this.rule,
    this.align,
  });

  final RunLook run;

  /// Points.
  final double before;
  final double after;
  final double left;
  final double right;

  /// A multiple of single spacing.
  final double line;

  /// The colour of a rule down the left side, 0xRRGGBB.
  final int? rule;

  /// 'center', 'right' or 'justify', or null for the start.
  final String? align;
}

/// A flag the editor's text sets on or off, or leaves to the line's look.
bool _flag(Object? value, bool line) => value is bool ? value : line;

String _hexOf(int rgb) => '#${(rgb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _sizeText(double points) =>
    points == points.roundToDouble() ? points.toInt().toString() : points.toString();

int? _rgbOf(Object? hex) {
  if (hex is! String) return null;
  final v = hex.startsWith('#') ? hex.substring(1) : hex;
  if (v.length != 6) return null;
  return int.tryParse(v, radix: 16);
}

double? _sizeOf(Object? value) => switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };

/// Something in a paragraph the editor keeps whole: a picture, a shape, a
/// field, a tracked change, a page break, a note mark. It is shown, and
/// written back as it was.
class KeptInline {
  KeptInline(this.id, this.nodes, this.text, {this.imagePart, this.width, this.height, this.kind = 'text'});
  final String id;
  final List<XmlNode> nodes;

  /// What it reads as.
  final String text;

  /// The picture's part in the package, for one that is a picture.
  final String? imagePart;
  final double? width;
  final double? height;

  /// 'image', 'shape', 'glyph', 'inserted', 'deleted', 'note', 'break',
  /// 'text' or 'hidden'.
  final String kind;
}

/// Something at body level the editor keeps whole: a table, a content
/// control, a field running across paragraphs, a section break.
class KeptBlock {
  KeptBlock(
    this.id,
    this.elements,
    this.text, {
    this.kind = 'block',
    this.table,
    this.lines = const <String>[],
    this.sectPr,
  });

  final String id;
  final List<XmlElement> elements;
  final String text;

  /// 'table', 'field', 'section' or 'block'.
  final String kind;
  final KeptTable? table;

  /// A field's paragraphs as text, for showing it.
  final List<String> lines;

  /// A section break's properties.
  final XmlElement? sectPr;

  XmlElement get element => elements.first;

  /// A table's cells as text.
  List<List<String>> get rows => <List<String>>[
        for (final row in table?.rows ?? const <List<KeptCell>>[])
          <String>[for (final cell in row) cell.text],
      ];
}

/// A table as it is drawn: its columns' widths and its cells.
class KeptTable {
  const KeptTable(this.widths, this.rows, {this.border});

  /// Points, one for each column of the table's grid.
  final List<double> widths;
  final List<List<KeptCell>> rows;

  /// The colour of the lines between cells, or null when it has none.
  final int? border;
}

class KeptCell {
  const KeptCell(
    this.text,
    this.look, {
    this.span = 1,
    this.fill,
    this.align,
    this.continued = false,
  });

  final String text;
  final RunLook look;

  /// How many of the grid's columns it takes.
  final int span;
  final int? fill;
  final String? align;

  /// True for a cell merged into the one above it.
  final bool continued;
}

class _Style {
  _Style(this.id, this.type);
  final String id;
  final String type;
  String? name;
  String? basedOn;
  XmlElement? rPr;
  XmlElement? pPr;
  XmlElement? tblPr;
}

class _CharBase {
  const _CharBase(this.rPr, this.look, this.shown, this.attributes, this.link, {this.linkElement, this.inline = false});

  final XmlElement? rPr;

  /// The look the file gives it.
  final RunLook look;

  /// The look the editor drew it in, and the attributes that made it so.
  final RunLook shown;
  final Map<String, Object?> attributes;
  final String? link;
  final XmlElement? linkElement;

  /// True for the place something kept whole takes.
  final bool inline;
}

/// One paragraph as it was read: its element, and each character's run.
class _Para {
  _Para(this.element, this.index, this.styleId);
  final XmlElement element;

  /// Its place among the body's children.
  final int index;
  final String? styleId;
  final List<Object> pieces = <Object>[]; // String (text) or KeptInline
  final List<_CharBase> chars = <_CharBase>[];

  /// Bookmarks, comment ranges and the like, each with the character it
  /// stands before.
  final List<(int, XmlElement)> marks = <(int, XmlElement)>[];
  Map<String, Object?> lineAttributes = const <String, Object?>{};
  late _CharBase plain;
  XmlElement? get pPr => element.getElement('w:pPr');
  XmlElement? get sectPr => pPr?.getElement('w:sectPr');

  bool get isEmpty => pieces.every((p) => p is KeptInline && p.kind == 'hidden');

  String get text {
    final out = StringBuffer();
    for (final piece in pieces) {
      out.write(piece is String ? piece : '￼');
    }
    return out.toString();
  }
}

class _Line {
  _Line(this.ops, this.attributes);
  final List<DeltaOp> ops;
  final Map<String, Object?> attributes;

  String get key => jsonEncode(<Object?>[ops, attributes]);

  String get text {
    final out = StringBuffer();
    for (final op in ops) {
      final insert = op['insert'];
      out.write(insert is String ? insert : '￼');
    }
    return out.toString();
  }

  String? get blockId {
    if (ops.length != 1) return null;
    final insert = ops.single['insert'];
    if (insert is Map && insert.containsKey(kBlockEmbed)) return insert[kBlockEmbed] as String?;
    return null;
  }
}

/// One element of the body as it is written: one read from the file, kept
/// as its own bytes, or one made anew.
class _Out {
  _Out.original(this.index, this.element) : made = false;
  _Out.made(this.element)
      : index = -1,
        made = true;
  final int index;
  final XmlElement element;
  final bool made;
}

/// A list a paragraph is in: its kind and the numbering it takes.
typedef _ListRef = ({String kind, String numId});

/// For each character of [now], the character of [old] it was kept from, or
/// -1 for one typed: the longest common run of characters, so two changes
/// apart in one line leave everything between them as it was.
List<int> alignText(String old, String now) {
  final n = old.length, m = now.length;
  final out = List<int>.filled(m, -1);
  var p = 0;
  while (p < n && p < m && old.codeUnitAt(p) == now.codeUnitAt(p)) {
    out[p] = p;
    p++;
  }
  var s = 0;
  while (s < n - p && s < m - p && old.codeUnitAt(n - 1 - s) == now.codeUnitAt(m - 1 - s)) {
    out[m - 1 - s] = n - 1 - s;
    s++;
  }
  final a0 = p, a1 = n - s, b0 = p, b1 = m - s;
  final rows = a1 - a0, cols = b1 - b0;
  if (rows == 0 || cols == 0 || rows * cols > 4000000) return out;
  final table = List<Uint16List>.generate(rows + 1, (_) => Uint16List(cols + 1));
  for (var i = rows - 1; i >= 0; i--) {
    final row = table[i], below = table[i + 1];
    final a = old.codeUnitAt(a0 + i);
    for (var j = cols - 1; j >= 0; j--) {
      row[j] = a == now.codeUnitAt(b0 + j) ? below[j + 1] + 1 : math.max(below[j], row[j + 1]);
    }
  }
  var i = 0, j = 0;
  while (i < rows && j < cols) {
    if (old.codeUnitAt(a0 + i) == now.codeUnitAt(b0 + j)) {
      out[b0 + j] = a0 + i;
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

/// One new line's share of the paragraphs it was made from: the character
/// each of its characters takes its run from, and the marks that now fall
/// in it.
class _Slice {
  const _Slice(this.bases, this.marks);
  final List<_CharBase> bases;
  final List<(int, XmlElement)> marks;
}

/// A Word document as lines of text the editor can change, with the look
/// each piece of text has, and the way back into the file.
///
/// Only the paragraphs that change are written again: every other element
/// of the body is written back as the very text it was read from, and every
/// other part of the package as it was. A changed paragraph keeps its
/// paragraph properties, its bookmarks and comment ranges where they stood,
/// and each character keeps the run properties it had, with only what the
/// reader changed written on top.
///
/// The editor shows each line in the look of its paragraph style, heading,
/// quote or body text, and each piece of text carries only what sets it
/// apart from that, so a paragraph given another style looks it at once.
class DocxDelta {
  DocxDelta._(this._package);

  factory DocxDelta.read(Uint8List bytes) {
    final doc = DocxDelta._(OoxmlPackage(bytes));
    doc._read();
    return doc;
  }

  final OoxmlPackage _package;
  static const _part = 'word/document.xml';

  final Map<String, _Style> _styles = <String, _Style>{};
  XmlElement? _defaultRPr;
  XmlElement? _defaultPPr;
  String? _defaultParagraphStyle;
  String? _bodyStyle;
  String _majorFont = 'Calibri Light';
  String _minorFont = 'Calibri';
  final Map<String, Map<int, String>> _numFormats = <String, Map<int, String>>{};
  final Map<String, String> _links = <String, String>{};

  late final String _text;
  (int, int)? _content;
  List<(int, int)>? _spans;
  late final List<XmlElement> _children;
  final List<Object> _units = <Object>[]; // _Para or KeptBlock
  final List<List<int>> _before = <List<int>>[];
  final Map<String, int> _blockUnit = <String, int>{};
  final Map<String, List<int>> _blockAt = <String, List<int>>{};
  final Map<String, _Para> _carrier = <String, _Para>{};
  List<int> _trailing = const <int>[];
  int? _sectPr;
  final Map<String, KeptInline> inlines = <String, KeptInline>{};
  final Map<String, KeptBlock> blocks = <String, KeptBlock>{};
  late final List<_Line> _lines;
  final Map<String, ParagraphLook> _looks = <String, ParagraphLook>{};

  /// The document as the editor starts from it.
  late final List<DeltaOp> ops;

  /// The bytes of a picture in the package.
  Uint8List? partBytes(String name) => _package.bytesOf(name);

  /// The look lines of a kind are drawn in: a heading of [header] 1 to 6, a
  /// quotation, or body text.
  ParagraphLook lineLook({int header = 0, bool quote = false}) =>
      _looks.putIfAbsent('$header/$quote', () {
        if (header > 0) {
          final id = _findHeadingStyle(header);
          if (id != null) return _paragraphLook(id);
          final body = _paragraphLook(_defaultParagraphStyle);
          return ParagraphLook(
            body.run.copyWith(bold: true, size: const <int, double>{1: 16, 2: 13, 3: 12}[header] ?? 11),
            before: 12,
            after: 3,
            line: body.line,
          );
        }
        if (quote) {
          final id = _findStyleNamed(const <String>{'quote', 'intense quote'});
          if (id != null) return _paragraphLook(id);
        }
        return _paragraphLook(_bodyStyle ?? _defaultParagraphStyle);
      });

  /// Every typeface the document names, for the text-format sheet.
  List<String> get fonts {
    final out = <String>{};
    void add(XmlElement? rPr) {
      final fonts = rPr?.getElement('w:rFonts');
      if (fonts == null) return;
      final theme = fonts.getAttribute('w:asciiTheme') ?? fonts.getAttribute('w:hAnsiTheme');
      final name = theme != null ? _themeFont(theme) : fonts.getAttribute('w:ascii') ?? fonts.getAttribute('w:hAnsi');
      if (name != null && name.isNotEmpty) out.add(name);
    }

    add(_defaultRPr);
    for (final style in _styles.values) {
      add(style.rPr);
    }
    for (final e in _package.part(_part)?.rootElement.descendantElements ?? const <XmlElement>[]) {
      if (e.name.local == 'rPr') add(e);
    }
    return out.toList()..sort();
  }

  // Reading.

  void _read() {
    final text = _package.textOf(_part);
    final doc = _package.part(_part);
    if (text == null || doc == null) throw const FormatException('no word/document.xml');
    _text = text;
    final body = doc.rootElement.getElement('w:body');
    if (body == null) throw const FormatException('no document body');
    _loadTheme();
    _loadStyles();
    _loadNumbering();
    _links.addAll(_package.relationships(_part));
    _children = body.childElements.toList();
    _locate();
    _bodyStyle = _commonBodyStyle();
    var pending = <int>[];
    var blockCount = 0;
    var sectionCount = 0;

    void block(KeptBlock kept, List<int> at, List<int> before) {
      blocks[kept.id] = kept;
      _blockAt[kept.id] = at;
      _blockUnit[kept.id] = _units.length;
      _units.add(kept);
      _before.add(before);
    }

    for (var k = 0; k < _children.length; k++) {
      final child = _children[k];
      final local = child.name.local;
      if (local == 'sectPr') {
        _sectPr = k;
        continue;
      }
      if (_invisible.contains(local)) {
        pending.add(k);
        continue;
      }
      if (local == 'p' && _fieldDepth(child) > 0) {
        // A field that runs on past its paragraph, such as a table of
        // contents: kept whole down to the paragraph it ends in.
        var depth = _fieldDepth(child);
        var end = k;
        while (depth > 0 && end + 1 < _children.length && _children[end + 1].name.local != 'sectPr') {
          end++;
          depth += _fieldDepth(_children[end]);
        }
        if (depth > 0) end = k;
        final elements = _children.sublist(k, end + 1);
        final lines = <String>[
          for (final e in elements)
            if (e.name.local == 'p') _plainText(e),
        ];
        block(
          KeptBlock('b${blockCount++}', elements, lines.join('\n'), kind: 'field', lines: lines),
          <int>[for (var i = k; i <= end; i++) i],
          pending,
        );
        pending = <int>[];
        k = end;
        continue;
      }
      if (local == 'p') {
        final para = _paragraph(child, k);
        final sect = para.sectPr;
        if (sect == null) {
          _units.add(para);
          _before.add(pending);
        } else if (para.isEmpty) {
          block(KeptBlock('s${sectionCount++}', <XmlElement>[child], '', kind: 'section', sectPr: sect), <int>[k], pending);
        } else {
          _units.add(para);
          _before.add(pending);
          final id = 's${sectionCount++}';
          _carrier[id] = para;
          block(KeptBlock(id, const <XmlElement>[], '', kind: 'section', sectPr: sect), const <int>[], const <int>[]);
        }
        pending = <int>[];
        continue;
      }
      block(
        KeptBlock(
          'b${blockCount++}',
          <XmlElement>[child],
          child.innerText.trim(),
          kind: local == 'tbl' ? 'table' : 'block',
          table: local == 'tbl' ? _tableOf(child) : null,
        ),
        <int>[k],
        pending,
      );
      pending = <int>[];
    }
    // Markers after the last unit ride with the section properties.
    _trailing = pending;
    _lines = <_Line>[for (final unit in _units) _lineOf(unit)];
    ops = <DeltaOp>[
      for (final line in _lines) ...<DeltaOp>[
        ...line.ops,
        <String, Object?>{
          'insert': '\n',
          if (line.attributes.isNotEmpty) 'attributes': line.attributes,
        },
      ],
    ];
    if (ops.isEmpty) ops.add(<String, Object?>{'insert': '\n'});
  }

  /// Where each child of the body sits in the part's text, so an element
  /// nobody changed is written back as the very text it was read from.
  void _locate() {
    try {
      final spans = <(int, int)>[];
      var depth = 0;
      var inBody = false;
      int? from, to, start;
      for (final event in parseEvents(_text, withLocation: true)) {
        if (event is XmlStartElementEvent) {
          final local = _localOf(event.name);
          if (depth == 1 && local == 'body' && from == null) {
            if (event.isSelfClosing) return;
            inBody = true;
            from = event.stop;
          } else if (inBody && depth == 2) {
            if (event.isSelfClosing) {
              spans.add((event.start!, event.stop!));
            } else {
              start = event.start;
            }
          }
          if (!event.isSelfClosing) depth++;
        } else if (event is XmlEndElementEvent) {
          depth--;
          if (inBody && depth == 2) {
            spans.add((start!, event.stop!));
          } else if (inBody && depth == 1) {
            to = event.start;
            inBody = false;
          }
        }
      }
      if (from != null && to != null && spans.length == _children.length) {
        _content = (from, to);
        _spans = spans;
      }
    } on Object {
      // The part is written whole instead.
    }
  }

  static String _localOf(String name) {
    final colon = name.indexOf(':');
    return colon < 0 ? name : name.substring(colon + 1);
  }

  static const _invisible = <String>{
    'bookmarkStart', 'bookmarkEnd', 'proofErr', 'permStart', 'permEnd',
    'commentRangeStart', 'commentRangeEnd', 'moveFromRangeStart',
    'moveFromRangeEnd', 'moveToRangeStart', 'moveToRangeEnd',
  };

  static const _marks = <String>{
    'bookmarkStart', 'bookmarkEnd', 'commentRangeStart', 'commentRangeEnd',
    'permStart', 'permEnd', 'moveFromRangeStart', 'moveFromRangeEnd',
    'moveToRangeStart', 'moveToRangeEnd',
  };

  static bool _opens(XmlElement mark) => mark.name.local.endsWith('Start');

  /// How many fields a paragraph opens and does not close.
  static int _fieldDepth(XmlElement p) {
    var depth = 0;
    for (final e in p.descendantElements) {
      if (e.name.local != 'fldChar') continue;
      final type = e.getAttribute('w:fldCharType');
      if (type == 'begin') depth++;
      if (type == 'end') depth--;
    }
    return depth;
  }

  /// What a paragraph or run reads as: its text, tabs and breaks.
  static String _plainText(XmlElement e) {
    final out = StringBuffer();
    for (final d in e.descendantElements) {
      switch (d.name.local) {
        case 't' || 'delText':
          out.write(d.innerText);
        case 'tab' || 'ptab':
          out.write('\t');
        case 'br' || 'cr':
          out.write(' ');
      }
    }
    return out.toString();
  }

  /// The paragraph style most body paragraphs are in: what "Normal text"
  /// means in this document.
  String? _commonBodyStyle() {
    final counts = <String, int>{};
    for (final child in _children) {
      if (child.name.local != 'p') continue;
      final pPr = child.getElement('w:pPr');
      if (pPr?.getElement('w:numPr') != null) continue;
      final id = pPr?.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
      if (id == null || _headingOf(id) != null || _isQuote(id) || _styleNumPr(id) != null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return _defaultParagraphStyle;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  _Line _lineOf(Object unit) {
    if (unit is KeptBlock) {
      return _Line(<DeltaOp>[
        <String, Object?>{
          'insert': <String, Object?>{kBlockEmbed: unit.id},
        },
      ], const <String, Object?>{});
    }
    final para = unit as _Para;
    final ops = <DeltaOp>[];
    var at = 0;
    for (final piece in para.pieces) {
      if (piece is KeptInline) {
        ops.add(<String, Object?>{
          'insert': <String, Object?>{kInlineEmbed: piece.id},
        });
        at++;
        continue;
      }
      final text = piece as String;
      var start = 0;
      for (var i = 1; i <= text.length; i++) {
        final ends = i == text.length || !_sameBase(para.chars[at + i - 1], para.chars[at + i]);
        if (!ends) continue;
        final chunk = text.substring(start, i);
        final attributes = _attributesOf(para.chars[at + start]);
        ops.add(<String, Object?>{
          'insert': chunk,
          if (attributes.isNotEmpty) 'attributes': attributes,
        });
        start = i;
      }
      at += text.length;
    }
    return _Line(_merged(ops), para.lineAttributes);
  }

  /// True when two characters were written with the same run properties,
  /// so they can share a run again.
  static bool _sameRun(_CharBase a, _CharBase b) =>
      identical(a, b) || (a.link == b.link && _rPrText(a) == _rPrText(b));

  static final Expando<String> _rPrTexts = Expando<String>();

  static String _rPrText(_CharBase base) => _rPrTexts[base] ??= base.rPr?.toXmlString() ?? '';

  static bool _sameBase(_CharBase a, _CharBase b) =>
      jsonEncode(_attributesOf(a)) == jsonEncode(_attributesOf(b));

  static Map<String, Object?> _attributesOf(_CharBase base) => <String, Object?>{
        ...base.attributes,
        if (base.link != null) 'link': base.link,
      };

  static List<DeltaOp> _merged(List<DeltaOp> ops) {
    final out = <DeltaOp>[];
    for (final op in ops) {
      final last = out.isEmpty ? null : out.last;
      if (last != null &&
          last['insert'] is String &&
          op['insert'] is String &&
          jsonEncode(last['attributes']) == jsonEncode(op['attributes'])) {
        out[out.length - 1] = <String, Object?>{
          'insert': (last['insert']! as String) + (op['insert']! as String),
          if (last['attributes'] != null) 'attributes': last['attributes'],
        };
      } else {
        out.add(op);
      }
    }
    return out;
  }

  _Para _paragraph(XmlElement p, int index) {
    final pPr = p.getElement('w:pPr');
    final styleId = pPr?.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
    final para = _Para(p, index, styleId);
    para.lineAttributes = _lineAttributesOf(pPr, styleId);
    final base = _baseOf(para.lineAttributes);
    final plainLook = _lookOf(null, styleId);
    final plainShown = plainLook.over(base);
    para.plain = _CharBase(null, plainLook, base.withAttributes(plainShown), plainShown, null);
    final inlineBase = _CharBase(null, plainLook, base.withAttributes(plainShown), plainShown, null, inline: true);
    final text = StringBuffer();
    var field = <XmlNode>[];
    var fieldDepth = 0;
    var fieldText = StringBuffer();
    var inResult = false;

    void flushText() {
      if (text.isEmpty) return;
      para.pieces.add(text.toString());
      text.clear();
    }

    void keep(KeptInline inline) {
      flushText();
      inlines[inline.id] = inline;
      para.pieces.add(inline);
      para.chars.add(inlineBase);
    }

    void addRun(XmlElement r, String? link, XmlElement? linkElement) {
      final rPr = r.getElement('w:rPr');
      if (fieldDepth > 0) {
        field.add(r);
      }
      for (final c in r.childElements) {
        final local = c.name.local;
        if (local == 'fldChar') {
          final type = c.getAttribute('w:fldCharType');
          if (type == 'begin') {
            if (fieldDepth == 0) {
              flushText();
              field = <XmlNode>[r];
              fieldText = StringBuffer();
              inResult = false;
            }
            fieldDepth++;
          } else if (type == 'separate') {
            if (fieldDepth == 1) inResult = true;
          } else if (type == 'end') {
            fieldDepth--;
            if (fieldDepth == 0) {
              keep(KeptInline('i${inlines.length}', field, fieldText.toString()));
              field = <XmlNode>[];
            }
          }
          continue;
        }
        if (fieldDepth > 0) {
          if (inResult && local == 't') fieldText.write(c.innerText);
          continue;
        }
      }
      if (fieldDepth > 0 || r.getElement('w:fldChar') != null) return;
      final hidden = rPr?.getElement('w:vanish') != null;
      final words = r.childElements.where((c) => _isPlain(c) && c.name.local != 'rPr' && c.name.local != 'lastRenderedPageBreak');
      if (!hidden && words.isNotEmpty && r.childElements.any((c) => !_isPlain(c))) {
        // Words sharing a run with a page break or a symbol are read as a
        // run of words and a run of the break, so the words can be seen,
        // found and changed, and the break stays where it was.
        final pieces = <List<XmlElement>>[];
        var plain = <XmlElement>[];
        for (final c in r.childElements) {
          if (c.name.local == 'rPr') continue;
          if (_isPlain(c)) {
            plain.add(c);
            continue;
          }
          if (plain.isNotEmpty) pieces.add(plain);
          plain = <XmlElement>[];
          pieces.add(<XmlElement>[c]);
        }
        if (plain.isNotEmpty) pieces.add(plain);
        for (final piece in pieces) {
          addRun(
            XmlElement(_w('r'), <XmlAttribute>[for (final a in r.attributes) a.copy()], <XmlNode>[
              if (rPr != null) rPr.copy(),
              for (final c in piece) c.copy(),
            ]),
            link,
            linkElement,
          );
        }
        return;
      }
      if (hidden || r.childElements.any((c) => !_isPlain(c))) {
        keep(_keptRun(r, hidden));
        return;
      }
      final look = _lookOf(rPr, styleId);
      final attributes = look.over(base);
      final charBase = _CharBase(rPr, look, base.withAttributes(attributes), attributes, link, linkElement: linkElement);
      for (final c in r.childElements) {
        final String? chunk = switch (c.name.local) {
          't' => c.innerText,
          'tab' => '\t',
          'br' || 'cr' => kSoftBreak,
          'noBreakHyphen' => '‑',
          'softHyphen' => '­',
          _ => null,
        };
        if (chunk == null || chunk.isEmpty) continue;
        text.write(chunk);
        for (var i = 0; i < chunk.length; i++) {
          para.chars.add(charBase);
        }
      }
    }

    void walk(XmlElement e, String? link, XmlElement? linkElement) {
      for (final c in e.childElements) {
        final local = c.name.local;
        if (local == 'pPr' || local == 'proofErr') continue;
        if (local == 'r') {
          addRun(c, link, linkElement);
          continue;
        }
        if (fieldDepth > 0) {
          field.add(c);
          continue;
        }
        if (_marks.contains(local)) {
          flushText();
          para.marks.add((para.chars.length, c));
          continue;
        }
        switch (local) {
          case 'hyperlink':
            final rid = c.getAttribute('r:id') ?? c.getAttribute('id', namespaceUri: kRelNs);
            final anchor = c.getAttribute('w:anchor');
            final target = rid != null ? _links[rid] : null;
            walk(c, target ?? (anchor != null ? '#$anchor' : link), c);
          case 'smartTag' || 'customXml' || 'dir' || 'bdo':
            walk(c, link, linkElement);
          case 'ins' || 'moveTo':
            // Someone else's tracked insertion: shown, and kept as theirs.
            keep(KeptInline('i${inlines.length}', <XmlNode>[c], _plainText(c), kind: 'inserted'));
          case 'del' || 'moveFrom':
            // Someone else's tracked deletion: shown struck through, and
            // kept as theirs.
            keep(KeptInline('i${inlines.length}', <XmlNode>[c], _plainText(c), kind: 'deleted'));
          default:
            // A simple field, a content control, maths: kept whole and
            // shown by what it reads.
            keep(KeptInline('i${inlines.length}', <XmlNode>[c], _plainText(c)));
        }
      }
    }

    walk(p, null, null);
    flushText();
    return para;
  }

  /// A child of a run the editor can take apart and put back together.
  static bool _isPlain(XmlElement c) {
    switch (c.name.local) {
      case 'rPr' || 't' || 'tab' || 'cr' || 'noBreakHyphen' || 'softHyphen' || 'lastRenderedPageBreak':
        return true;
      case 'br':
        return c.attributes.every((a) => a.name.local == 'type' && a.value == 'textWrapping');
    }
    return false;
  }

  /// A run the editor keeps whole, with what to show in its place.
  KeptInline _keptRun(XmlElement r, bool hidden) {
    final id = 'i${inlines.length}';
    final nodes = <XmlNode>[r];
    if (hidden) return KeptInline(id, nodes, '', kind: 'hidden');
    final (part, w, h) = _pictureOf(r);
    if (part != null) return KeptInline(id, nodes, '', imagePart: part, width: w, height: h, kind: 'image');
    final all = r.descendantElements.toList();
    bool has(String local) => all.any((e) => e.name.local == local);
    final box = all.where((e) => e.name.local == 'txbxContent').firstOrNull;
    if (box != null) return KeptInline(id, nodes, _plainText(box).trim(), kind: 'shape');
    if (has('drawing') || has('pict') || has('object')) return KeptInline(id, nodes, '', kind: 'shape');
    final fallback = all.where((e) => e.name.local == 'Fallback').firstOrNull;
    if (fallback != null) return KeptInline(id, nodes, _plainText(fallback), kind: 'glyph');
    for (final c in r.childElements) {
      switch (c.name.local) {
        case 'br':
          final type = c.getAttribute('w:type');
          if (type == 'page' || type == 'column') return KeptInline(id, nodes, '', kind: 'break');
        case 'footnoteReference' || 'endnoteReference':
          return KeptInline(id, nodes, '*', kind: 'note');
        case 'commentReference' || 'annotationRef':
          return KeptInline(id, nodes, '', kind: 'hidden');
        case 'sym':
          final code = int.tryParse(c.getAttribute('w:char') ?? '', radix: 16);
          return KeptInline(id, nodes, _symbol(c.getAttribute('w:font'), code), kind: 'glyph');
        case 'ptab':
          return KeptInline(id, nodes, '\t', kind: 'glyph');
        case 'ruby':
          final ruby = c.getElement('w:rubyBase');
          return KeptInline(id, nodes, ruby == null ? '' : _plainText(ruby), kind: 'glyph');
      }
    }
    return KeptInline(id, nodes, _plainText(r));
  }

  (String?, double?, double?) _pictureOf(XmlElement run) {
    String? rid;
    double? w, h;
    for (final e in run.descendantElements) {
      final local = e.name.local;
      if (local == 'blip' || local == 'imagedata') {
        rid ??= e.getAttribute('r:embed') ?? e.getAttribute('r:id') ?? e.getAttribute('embed', namespaceUri: kRelNs);
      } else if (local == 'extent' && w == null) {
        final cx = double.tryParse(e.getAttribute('cx') ?? '');
        final cy = double.tryParse(e.getAttribute('cy') ?? '');
        if (cx != null) w = cx / 12700;
        if (cy != null) h = cy / 12700;
      }
    }
    return (rid == null ? null : _links[rid], w, h);
  }

  KeptTable _tableOf(XmlElement tbl) {
    final widths = <double>[
      for (final col in tbl.getElement('w:tblGrid')?.childElements ?? const <XmlElement>[])
        if (col.name.local == 'gridCol') (double.tryParse(col.getAttribute('w:w') ?? '') ?? 0) / 20,
    ];
    final tblPr = tbl.getElement('w:tblPr');
    final tableStyle = tblPr?.getElement('w:tblStyle')?.getAttribute('w:val');
    final border = _borderOf(tblPr) ?? _borderOf(_styles[tableStyle]?.tblPr);
    final rows = <List<KeptCell>>[];
    for (final tr in tbl.childElements.where((e) => e.name.local == 'tr')) {
      final cells = <KeptCell>[];
      for (final tc in tr.childElements.where((e) => e.name.local == 'tc')) {
        final tcPr = tc.getElement('w:tcPr');
        final span = int.tryParse(tcPr?.getElement('w:gridSpan')?.getAttribute('w:val') ?? '') ?? 1;
        final merge = tcPr?.getElement('w:vMerge');
        final fill = tcPr?.getElement('w:shd')?.getAttribute('w:fill');
        final paragraphs = tc.childElements.where((e) => e.name.local == 'p').toList();
        final first = paragraphs.firstOrNull;
        final pPr = first?.getElement('w:pPr');
        final styleId = pPr?.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
        final run = first?.descendantElements.where((e) => e.name.local == 'r' && e.getElement('w:t') != null).firstOrNull;
        cells.add(KeptCell(
          paragraphs.map(_plainText).join('\n'),
          _lookOf(run?.getElement('w:rPr'), styleId),
          span: span < 1 ? 1 : span,
          fill: fill == null || fill == 'auto' ? null : int.tryParse(fill, radix: 16),
          align: _alignOf(pPr, styleId),
          continued: merge != null && (merge.getAttribute('w:val') ?? 'continue') != 'restart',
        ));
      }
      rows.add(cells);
    }
    return KeptTable(widths, rows, border: border);
  }

  static int? _borderOf(XmlElement? tblPr) {
    final borders = tblPr?.getElement('w:tblBorders');
    final line = borders?.getElement('w:insideH') ?? borders?.getElement('w:top');
    if (line == null) return null;
    final val = line.getAttribute('w:val');
    if (val == null || val == 'nil' || val == 'none') return null;
    final colour = line.getAttribute('w:color');
    return colour == null || colour == 'auto' ? 0 : int.tryParse(colour, radix: 16) ?? 0;
  }

  /// The look a line of [attributes] is drawn in, which the text on it is
  /// told apart from.
  RunLook _baseOf(Map<String, Object?> attributes) => lineLook(
        header: (attributes['header'] as num?)?.toInt() ?? 0,
        quote: attributes['blockquote'] == true,
      ).run;

  Map<String, Object?> _lineAttributesOf(XmlElement? pPr, String? styleId) {
    final out = <String, Object?>{};
    final level = _headingOf(styleId);
    if (level != null && level >= 1 && level <= 6) {
      out['header'] = level;
    } else if (_isQuote(styleId)) {
      out['blockquote'] = true;
    }
    final (numId, ilvl) = _numberingOf(pPr, styleId);
    if (numId != null) {
      out['list'] = _kindOf(numId, ilvl);
      if (ilvl > 0) out['indent'] = ilvl;
    } else {
      final left = int.tryParse(
            pPr?.getElement('w:ind')?.getAttribute('w:left') ??
                pPr?.getElement('w:ind')?.getAttribute('w:start') ??
                '',
          ) ??
          0;
      final steps = (left / 720).round();
      if (steps > 0) out['indent'] = steps.clamp(1, 8);
    }
    final align = _alignOf(pPr, styleId);
    if (align != null) out['align'] = align;
    return out;
  }

  /// The numbering a paragraph takes, directly or from its style, and its
  /// level; a null number when it is not in a list.
  (String?, int) _numberingOf(XmlElement? pPr, String? styleId) {
    final direct = pPr?.getElement('w:numPr');
    final styled = _styleNumPr(styleId);
    final numId = direct?.getElement('w:numId')?.getAttribute('w:val') ??
        styled?.getElement('w:numId')?.getAttribute('w:val');
    final ilvl = int.tryParse(direct?.getElement('w:ilvl')?.getAttribute('w:val') ??
            styled?.getElement('w:ilvl')?.getAttribute('w:val') ??
            '0') ??
        0;
    if (numId == null || numId == '0' || !_numFormats.containsKey(numId)) return (null, 0);
    return (numId, ilvl);
  }

  String _kindOf(String numId, int level) {
    final formats = _numFormats[numId];
    final format = formats?[level] ?? formats?[0] ?? 'bullet';
    return format == 'bullet' || format == 'none' ? 'bullet' : 'ordered';
  }

  String? _alignOf(XmlElement? pPr, String? styleId) {
    String? jc = pPr?.getElement('w:jc')?.getAttribute('w:val');
    var id = styleId;
    var guard = 0;
    while (jc == null && id != null && guard++ < 12) {
      final style = _styles[id];
      jc = style?.pPr?.getElement('w:jc')?.getAttribute('w:val');
      id = style?.basedOn;
    }
    return switch (jc) {
      'center' => 'center',
      'right' || 'end' => 'right',
      'both' || 'distribute' => 'justify',
      _ => null,
    };
  }

  XmlElement? _styleNumPr(String? styleId) {
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final style = _styles[id];
      final numPr = style?.pPr?.getElement('w:numPr');
      if (numPr != null) return numPr;
      id = style?.basedOn;
    }
    return null;
  }

  int? _headingOf(String? styleId) {
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final style = _styles[id];
      if (style == null) break;
      final outline = int.tryParse(style.pPr?.getElement('w:outlineLvl')?.getAttribute('w:val') ?? '');
      if (outline != null && outline < 6) return outline + 1;
      final name = (style.name ?? '').toLowerCase();
      if (name == 'title') return 1;
      final m = RegExp(r'^heading\s*(\d)$').firstMatch(name);
      if (m != null) return int.parse(m.group(1)!);
      id = style.basedOn;
    }
    final m = RegExp(r'^Heading(\d)$').firstMatch(styleId ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  bool _isQuote(String? styleId) {
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final style = _styles[id];
      if (style == null) return false;
      final name = (style.name ?? '').toLowerCase();
      if (name == 'quote' || name == 'intense quote') return true;
      id = style.basedOn;
    }
    return false;
  }

  String? _findHeadingStyle(int level) {
    for (final style in _styles.values) {
      if (style.type != 'paragraph') continue;
      final outline = int.tryParse(style.pPr?.getElement('w:outlineLvl')?.getAttribute('w:val') ?? '');
      final name = (style.name ?? '').toLowerCase();
      if (name == 'heading $level' || (outline == level - 1 && name != 'title')) return style.id;
    }
    return null;
  }

  String? _findStyleNamed(Set<String> names) {
    for (final style in _styles.values) {
      if (style.type == 'paragraph' && names.contains((style.name ?? '').toLowerCase())) return style.id;
    }
    return null;
  }

  /// The alignment a paragraph of a kind takes from its style, which a
  /// paragraph given that style is shown in.
  String? alignFor({int header = 0, bool quote = false}) => lineLook(header: header, quote: quote).align;

  ParagraphLook _paragraphLook(String? styleId) {
    final run = _lookOf(null, styleId);
    var before = 0.0, after = 0.0, line = 1.0, left = 0.0, right = 0.0;
    int? rule;
    double? points(String? twips) {
      final v = double.tryParse(twips ?? '');
      return v == null ? null : v / 20;
    }

    for (final pPr in <XmlElement>[
      ?_defaultPPr,
      ..._styleChain(styleId, (s) => s.pPr),
    ]) {
      final spacing = pPr.getElement('w:spacing');
      if (spacing != null) {
        before = points(spacing.getAttribute('w:before')) ?? before;
        after = points(spacing.getAttribute('w:after')) ?? after;
        final l = double.tryParse(spacing.getAttribute('w:line') ?? '');
        if (l != null) {
          final lineRule = spacing.getAttribute('w:lineRule') ?? 'auto';
          line = lineRule == 'auto' ? l / 240 : (l / 20) / (run.size * 1.17);
        }
      }
      final ind = pPr.getElement('w:ind');
      if (ind != null) {
        left = points(ind.getAttribute('w:left') ?? ind.getAttribute('w:start')) ?? left;
        right = points(ind.getAttribute('w:right') ?? ind.getAttribute('w:end')) ?? right;
      }
      final border = pPr.getElement('w:pBdr')?.getElement('w:left');
      if (border != null) {
        final val = border.getAttribute('w:val');
        final colour = border.getAttribute('w:color');
        rule = val == null || val == 'nil' || val == 'none'
            ? null
            : (colour == null || colour == 'auto' ? 0 : int.tryParse(colour, radix: 16) ?? 0);
      }
    }
    return ParagraphLook(
      run,
      before: before,
      after: after,
      line: line.clamp(0.8, 3.0),
      left: left,
      right: right,
      rule: rule,
      align: _alignOf(null, styleId),
    );
  }

  /// The look a run has once its paragraph's style, its own character style
  /// and its direct formatting are laid over the document's defaults.
  RunLook _lookOf(XmlElement? rPr, String? styleId) {
    final layers = <XmlElement>[
      ?_defaultRPr,
      ..._styleChain(styleId, (s) => s.rPr),
      ..._styleChain(rPr?.getElement('w:rStyle')?.getAttribute('w:val'), (s) => s.rPr),
      ?rPr,
    ];
    // Right-to-left and complex-script text takes its own bold, italic,
    // size and typeface.
    final complex = rPr != null && (_on(rPr.getElement('w:rtl')) || _on(rPr.getElement('w:cs')));
    var bold = false, italic = false, underline = false, strike = false;
    int? color, background;
    double? size;
    String? font;
    var script = 0;
    for (final layer in layers) {
      bool? flag(String tag) {
        final e = layer.getElement('w:$tag');
        return e == null ? null : _on(e);
      }

      bold = flag(complex ? 'bCs' : 'b') ?? bold;
      italic = flag(complex ? 'iCs' : 'i') ?? italic;
      strike = flag('strike') ?? flag('dstrike') ?? strike;
      final u = layer.getElement('w:u');
      if (u != null) underline = (u.getAttribute('w:val') ?? 'single') != 'none';
      final c = layer.getElement('w:color')?.getAttribute('w:val');
      if (c != null) color = c == 'auto' ? null : int.tryParse(c, radix: 16);
      final hl = layer.getElement('w:highlight')?.getAttribute('w:val');
      if (hl != null) background = hl == 'none' ? null : kHighlights[hl];
      final fill = layer.getElement('w:shd')?.getAttribute('w:fill');
      if (fill != null && fill != 'auto' && layer.getElement('w:highlight') == null) {
        background = int.tryParse(fill, radix: 16) ?? background;
      }
      final sz = double.tryParse(layer.getElement(complex ? 'w:szCs' : 'w:sz')?.getAttribute('w:val') ?? '');
      if (sz != null) size = sz / 2;
      final fonts = layer.getElement('w:rFonts');
      if (fonts != null) {
        final theme = complex
            ? fonts.getAttribute('w:cstheme')
            : fonts.getAttribute('w:asciiTheme') ?? fonts.getAttribute('w:hAnsiTheme');
        final named = complex ? fonts.getAttribute('w:cs') : fonts.getAttribute('w:ascii') ?? fonts.getAttribute('w:hAnsi');
        final name = theme != null ? _themeFont(theme) : named;
        if (name != null && name.isNotEmpty) font = name;
      }
      final va = layer.getElement('w:vertAlign')?.getAttribute('w:val');
      if (va != null) script = va == 'superscript' ? 1 : (va == 'subscript' ? -1 : 0);
    }
    return RunLook(
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      color: color,
      background: background,
      size: size ?? 10,
      font: font ?? 'Times New Roman',
      script: script,
    );
  }

  static bool _on(XmlElement? e) {
    if (e == null) return false;
    final v = e.getAttribute('w:val');
    return v == null || v == '1' || v == 'true' || v == 'on';
  }

  String _themeFont(String theme) => theme.startsWith('major') ? _majorFont : _minorFont;

  /// The properties a style and the styles it is based on give, the
  /// furthest first so the nearest wins.
  List<XmlElement> _styleChain(String? styleId, XmlElement? Function(_Style) pick) {
    final chain = <XmlElement>[];
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final style = _styles[id];
      if (style == null) break;
      final e = pick(style);
      if (e != null) chain.insert(0, e);
      id = style.basedOn;
    }
    return chain;
  }

  void _loadTheme() {
    final theme = _package.part('word/theme/theme1.xml');
    if (theme == null) return;
    for (final e in theme.rootElement.descendantElements) {
      final local = e.name.local;
      if (local != 'majorFont' && local != 'minorFont') continue;
      final latin = e.childElements.where((c) => c.name.local == 'latin').firstOrNull?.getAttribute('typeface');
      if (latin == null || latin.isEmpty) continue;
      if (local == 'majorFont') {
        _majorFont = latin;
      } else {
        _minorFont = latin;
      }
    }
  }

  void _loadStyles() {
    final doc = _package.part('word/styles.xml');
    if (doc == null) return;
    final root = doc.rootElement;
    final defaults = root.getElement('w:docDefaults');
    _defaultRPr = defaults?.getElement('w:rPrDefault')?.getElement('w:rPr');
    _defaultPPr = defaults?.getElement('w:pPrDefault')?.getElement('w:pPr');
    for (final s in root.childElements.where((e) => e.name.local == 'style')) {
      final id = s.getAttribute('w:styleId');
      if (id == null) continue;
      final style = _Style(id, s.getAttribute('w:type') ?? 'paragraph')
        ..name = s.getElement('w:name')?.getAttribute('w:val')
        ..basedOn = s.getElement('w:basedOn')?.getAttribute('w:val')
        ..rPr = s.getElement('w:rPr')
        ..pPr = s.getElement('w:pPr')
        ..tblPr = s.getElement('w:tblPr');
      _styles[id] = style;
      final isDefault = s.getAttribute('w:default');
      if (style.type == 'paragraph' && (isDefault == '1' || isDefault == 'true')) {
        _defaultParagraphStyle = id;
      }
    }
  }

  void _loadNumbering() {
    final doc = _package.part('word/numbering.xml');
    if (doc == null) return;
    final root = doc.rootElement;
    final abstracts = <String, Map<int, String>>{};
    for (final an in root.childElements.where((e) => e.name.local == 'abstractNum')) {
      final id = an.getAttribute('w:abstractNumId');
      if (id == null) continue;
      abstracts[id] = <int, String>{
        for (final lvl in an.childElements.where((e) => e.name.local == 'lvl'))
          int.tryParse(lvl.getAttribute('w:ilvl') ?? '0') ?? 0:
              lvl.getElement('w:numFmt')?.getAttribute('w:val') ?? 'bullet',
      };
    }
    for (final num in root.childElements.where((e) => e.name.local == 'num')) {
      final id = num.getAttribute('w:numId');
      final abstract = num.getElement('w:abstractNumId')?.getAttribute('w:val');
      if (id == null || abstract == null) continue;
      final formats = abstracts[abstract];
      if (formats != null) _numFormats[id] = formats;
    }
  }

  // Writing.

  /// The document with its body made from [edited], or exactly the bytes
  /// that were read when nothing changed.
  Uint8List write(List<DeltaOp> edited) {
    final lines = _linesOf(edited);
    if (lines.length == _lines.length &&
        List<int>.generate(lines.length, (i) => i).every((i) => lines[i].key == _lines[i].key)) {
      return _package.original;
    }
    final matches = _match(lines);
    final slices = _slices(lines, matches);
    final out = <_Out>[];
    final used = <int>{};
    _Para? lastSource;
    _ListRef? lastList;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final blockId = line.blockId;
      if (blockId != null) {
        final unit = _blockUnit[blockId];
        final block = blocks[blockId];
        if (unit == null || block == null || !used.add(unit)) continue;
        out.addAll(_before[unit].map(_original));
        if (block.kind == 'section') {
          _placeSection(out, block);
        } else {
          out.addAll(_blockAt[blockId]!.map(_original));
        }
        lastList = null;
        // A line typed after a table takes after the paragraph it was typed
        // into, never after one across the table.
        lastSource = null;
        continue;
      }
      final source = matches[i];
      final unit = source == null ? null : _units[source];
      final para = unit is _Para ? unit : null;
      final first = source != null && used.add(source);
      if (source != null && first) out.addAll(_before[source].map(_original));
      final next = i + 1 < lines.length ? lines[i + 1].blockId : null;
      if (para != null && first && line.key == _lines[source].key) {
        if (para.sectPr == null || (next != null && identical(_carrier[next], para))) {
          out.add(_original(para.index));
        } else {
          // Its section break has gone, or has been given to another
          // paragraph.
          final copy = para.element.copy();
          copy.getElement('w:pPr')?.getElement('w:sectPr')?.remove();
          out.add(_Out.made(copy));
        }
        lastSource = para;
        lastList = _listOf(out.last.element);
        continue;
      }
      final written = _paragraphFor(
        line,
        para ?? _freshSource(lines, matches, i, lastSource),
        fresh: para == null,
        before: lastList,
        after: _nextList(lines, matches, i),
        slice: slices[i],
      );
      out.add(_Out.made(written));
      if (para != null) lastSource = para;
      lastList = _listOf(written);
    }
    out.addAll(_trailing.map(_original));
    if (_sectPr != null) out.add(_original(_sectPr!));
    _package.replace(_part, _splice(out));
    return _package.write();
  }

  _Out _original(int index) => _Out.original(index, _children[index]);

  /// The paragraph a line with none of its own takes after: the one before
  /// it, or the one after it when the line is shaped like that one and not
  /// the one before, as Enter at a paragraph's start makes it.
  _Para? _freshSource(List<_Line> lines, List<int?> matches, int i, _Para? lastSource) {
    final next = _nextPara(lines, matches, i);
    if (lastSource == null) return next;
    final shape = lines[i].attributes;
    if (next != null && _sameShape(shape, next.lineAttributes) && !_sameShape(shape, lastSource.lineAttributes)) {
      return next;
    }
    return lastSource;
  }

  static bool _sameShape(Map<String, Object?> a, Map<String, Object?> b) {
    final keys = <String>{...a.keys, ...b.keys};
    return keys.every((k) => a[k] == b[k]);
  }

  /// The paragraph read from the file that the next line after [i] with one
  /// stands for, before any table or break.
  _Para? _nextPara(List<_Line> lines, List<int?> matches, int i) {
    for (var k = i + 1; k < lines.length; k++) {
      if (lines[k].blockId != null) return null;
      final source = matches[k];
      final unit = source == null ? null : _units[source];
      if (unit is _Para) return unit;
    }
    return null;
  }

  /// Each changed line's share of the paragraphs it was made from: a
  /// paragraph read from the file, the line that stands for it and the lines
  /// split off after it, and the paragraph after it when a join has brought
  /// its words onto the line.
  Map<int, _Slice> _slices(List<_Line> lines, List<int?> matches) {
    final out = <int, _Slice>{};
    final paired = <int>{for (final m in matches) ?m};
    final seen = <int>{};
    var i = 0;
    while (i < lines.length) {
      final source = matches[i];
      final unit = source == null ? null : _units[source];
      if (lines[i].blockId != null || unit is! _Para || !seen.add(source!)) {
        i++;
        continue;
      }
      final members = <int>[i];
      var j = i + 1;
      while (j < lines.length && lines[j].blockId == null && matches[j] == null) {
        members.add(j++);
      }
      final olds = <_Para>[unit];
      final next = source + 1 < _units.length ? _units[source + 1] : null;
      if (next is _Para && !paired.contains(source + 1) && next.text.isNotEmpty) {
        final tail = next.text.substring(math.max(0, next.text.length - 8));
        if (lines[members.last].text.endsWith(tail)) olds.add(next);
      }
      if (members.length > 1 || olds.length > 1 || lines[i].key != _lines[source].key) {
        final shares = _sliceGroup(<String>[for (final m in members) lines[m].text], olds);
        for (var k = 0; k < members.length; k++) {
          out[members[k]] = shares[k];
        }
      }
      i = j;
    }
    return out;
  }

  /// A section break put back: its own empty paragraph as it was, or given
  /// to the paragraph now last in its section.
  void _placeSection(List<_Out> out, KeptBlock block) {
    final at = _blockAt[block.id]!;
    if (at.isNotEmpty) {
      out.addAll(at.map(_original));
      return;
    }
    final sectPr = block.sectPr!;
    final last = out.isEmpty ? null : out.last;
    if (last != null && !last.made && identical(_carrier[block.id]?.element, last.element)) return;
    if (last != null &&
        last.element.name.local == 'p' &&
        last.element.getElement('w:pPr')?.getElement('w:sectPr') == null) {
      final element = last.made ? last.element : last.element.copy();
      final pPr = _ensure(element, 'pPr', _pPrOrder);
      _insertOrdered(pPr, sectPr.copy(), _pPrOrder);
      out[out.length - 1] = _Out.made(element);
      return;
    }
    out.add(_Out.made(XmlElement(_w('p'), const <XmlAttribute>[], <XmlNode>[
      XmlElement(_w('pPr'), const <XmlAttribute>[], <XmlNode>[sectPr.copy()]),
    ])));
  }

  String _splice(List<_Out> out) {
    final spans = _spans;
    final content = _content;
    if (spans == null || content == null) {
      final doc = _package.part(_part)!;
      doc.rootElement.getElement('w:body')!.children
        ..clear()
        ..addAll(out.map((o) => o.made ? o.element : o.element.copy()));
      return doc.toXmlString();
    }
    final b = StringBuffer(_text.substring(0, content.$1));
    for (final o in out) {
      if (o.made) {
        b.write(o.element.toXmlString());
      } else {
        final (start, stop) = spans[o.index];
        b.write(_text.substring(start, stop));
      }
    }
    b.write(_text.substring(content.$2));
    return b.toString();
  }

  _ListRef? _listOf(XmlElement p) {
    final numPr = p.getElement('w:pPr')?.getElement('w:numPr');
    final numId = numPr?.getElement('w:numId')?.getAttribute('w:val');
    if (numId == null || numId == '0' || !_numFormats.containsKey(numId)) return null;
    final level = int.tryParse(numPr?.getElement('w:ilvl')?.getAttribute('w:val') ?? '0') ?? 0;
    return (kind: _kindOf(numId, level), numId: numId);
  }

  _ListRef? _nextList(List<_Line> lines, List<int?> matches, int i) {
    if (i + 1 >= lines.length || lines[i + 1].attributes['list'] == null) return null;
    final source = matches[i + 1];
    final unit = source == null ? null : _units[source];
    return unit is _Para ? _listOf(unit.element) : null;
  }

  List<_Line> _linesOf(List<DeltaOp> raw) {
    final delta = normalizeOps(raw);
    final lines = <_Line>[];
    var current = <DeltaOp>[];
    for (final op in delta) {
      final insert = op['insert'];
      final attributes = (op['attributes'] as Map?)?.cast<String, Object?>();
      if (insert is String) {
        var rest = insert;
        while (rest.isNotEmpty) {
          final at = rest.indexOf('\n');
          if (at < 0) {
            current.add(<String, Object?>{
              'insert': rest,
              if (attributes != null && attributes.isNotEmpty) 'attributes': _inlineOnly(attributes),
            });
            break;
          }
          if (at > 0) {
            current.add(<String, Object?>{
              'insert': rest.substring(0, at),
              if (attributes != null && attributes.isNotEmpty) 'attributes': _inlineOnly(attributes),
            });
          }
          lines.addAll(_split(_Line(_merged(_clean(current)), _blockOnly(attributes))));
          current = <DeltaOp>[];
          rest = rest.substring(at + 1);
        }
      } else if (insert is Map) {
        current.add(<String, Object?>{'insert': Map<String, Object?>.of(insert.cast<String, Object?>())});
      }
    }
    if (current.isNotEmpty) lines.addAll(_split(_Line(_merged(_clean(current)), const <String, Object?>{})));
    return lines;
  }

  /// [line] with anything kept whole at body level, such as a table, taken
  /// onto a line of its own, so words typed beside it never take its place.
  static List<_Line> _split(_Line line) {
    if (line.ops.length < 2 || !line.ops.any(_isBlock)) return <_Line>[line];
    final out = <_Line>[];
    var words = <DeltaOp>[];
    for (final op in line.ops) {
      if (!_isBlock(op)) {
        words.add(op);
        continue;
      }
      if (words.isNotEmpty) out.add(_Line(words, line.attributes));
      words = <DeltaOp>[];
      out.add(_Line(<DeltaOp>[op], const <String, Object?>{}));
    }
    if (words.isNotEmpty) out.add(_Line(words, line.attributes));
    return out;
  }

  static bool _isBlock(DeltaOp op) {
    final insert = op['insert'];
    return insert is Map && insert.containsKey(kBlockEmbed);
  }

  static const _blockKeys = <String>{'header', 'list', 'indent', 'align', 'blockquote'};

  static Map<String, Object?> _blockOnly(Map<String, Object?>? attributes) => <String, Object?>{
        if (attributes != null)
          for (final e in attributes.entries)
            if (_blockKeys.contains(e.key) && e.value != null) e.key: e.value,
      };

  static Map<String, Object?> _inlineOnly(Map<String, Object?> attributes) => <String, Object?>{
        for (final e in attributes.entries)
          if (!_blockKeys.contains(e.key) && e.value != null) e.key: e.value,
      };

  static List<DeltaOp> _clean(List<DeltaOp> ops) => <DeltaOp>[
        for (final op in ops)
          if (op['attributes'] is Map && (op['attributes']! as Map).isEmpty)
            <String, Object?>{'insert': op['insert']}
          else
            op,
      ];

  /// Which paragraph read from the file each edited line stands for: the
  /// same line where it is unchanged, and otherwise the paragraph it took
  /// the place of, found by keeping the unchanged lines in order.
  List<int?> _match(List<_Line> lines) {
    final result = List<int?>.filled(lines.length, null);
    _diff(lines, 0, _lines.length, 0, lines.length, result);
    return result;
  }

  void _diff(List<_Line> b, int a0, int a1, int b0, int b1, List<int?> result) {
    final a = _lines;
    while (a0 < a1 && b0 < b1 && a[a0].key == b[b0].key) {
      result[b0++] = a0++;
    }
    while (a1 > a0 && b1 > b0 && a[a1 - 1].key == b[b1 - 1].key) {
      result[--b1] = --a1;
    }
    final n = a1 - a0, m = b1 - b0;
    if (n == 0 || m == 0) return;
    if (n * m <= 250000) {
      _commonRun(b, a0, a1, b0, b1, result);
      return;
    }
    // Too large to compare every pair: anchor on lines that appear once on
    // each side, keep the longest run of them in order, and compare the
    // stretches between.
    final seenA = <String, int>{}, seenB = <String, int>{};
    final atA = <String, int>{}, atB = <String, int>{};
    for (var i = a0; i < a1; i++) {
      final k = a[i].key;
      seenA[k] = (seenA[k] ?? 0) + 1;
      atA[k] = i;
    }
    for (var j = b0; j < b1; j++) {
      final k = b[j].key;
      seenB[k] = (seenB[k] ?? 0) + 1;
      atB[k] = j;
    }
    final pairs = <(int, int)>[
      for (final e in atB.entries)
        if (seenB[e.key] == 1 && seenA[e.key] == 1) (atA[e.key]!, e.value),
    ]..sort((x, y) => x.$2.compareTo(y.$2));
    final anchors = _increasing(pairs);
    if (anchors.isEmpty) {
      for (var k = 0; k < m && k < n; k++) {
        result[b0 + k] = a0 + k;
      }
      return;
    }
    var pa = a0, pb = b0;
    for (final (ia, ib) in anchors) {
      _diff(b, pa, ia, pb, ib, result);
      result[ib] = ia;
      pa = ia + 1;
      pb = ib + 1;
    }
    _diff(b, pa, a1, pb, b1, result);
  }

  /// The longest run of [pairs], already in order of their second, whose
  /// firsts also rise.
  static List<(int, int)> _increasing(List<(int, int)> pairs) {
    if (pairs.isEmpty) return const <(int, int)>[];
    final tails = <int>[];
    final back = List<int>.filled(pairs.length, -1);
    for (var i = 0; i < pairs.length; i++) {
      var lo = 0, hi = tails.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (pairs[tails[mid]].$1 < pairs[i].$1) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo > 0) back[i] = tails[lo - 1];
      if (lo == tails.length) {
        tails.add(i);
      } else {
        tails[lo] = i;
      }
    }
    final out = <(int, int)>[];
    for (var i = tails.last; i >= 0; i = back[i]) {
      out.add(pairs[i]);
    }
    return out.reversed.toList();
  }

  void _commonRun(List<_Line> b, int a0, int a1, int b0, int b1, List<int?> result) {
    final a = _lines;
    final n = a1 - a0, m = b1 - b0;
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = a[a0 + i].key == b[b0 + j].key
            ? table[i + 1][j + 1] + 1
            : math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    final gapA = <int>[], gapB = <int>[];
    void pairGap() {
      _pairGap(b, gapA, gapB, result);
      gapA.clear();
      gapB.clear();
    }

    while (i < n && j < m) {
      if (a[a0 + i].key == b[b0 + j].key) {
        pairGap();
        result[b0 + j] = a0 + i;
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        gapA.add(a0 + i);
        i++;
      } else {
        gapB.add(b0 + j);
        j++;
      }
    }
    while (i < n) {
      gapA.add(a0 + i++);
    }
    while (j < m) {
      gapB.add(b0 + j++);
    }
    pairGap();
  }

  /// Pairs the changed lines [gapB] with the paragraphs [gapA] they took the
  /// place of. The same number on each side pair in order, one for one; a
  /// gap where lines were added or taken away pairs each line with the
  /// paragraph whose words it shares most, in order, and a line sharing none
  /// is a new one, so a paragraph beside one deleted keeps its own
  /// properties and marks.
  void _pairGap(List<_Line> b, List<int> gapA, List<int> gapB, List<int?> result) {
    if (gapA.length == gapB.length) {
      for (var k = 0; k < gapB.length; k++) {
        result[gapB[k]] = gapA[k];
      }
      return;
    }
    if (gapA.isEmpty) return;
    final n = gapA.length, m = gapB.length;
    if (n * m > 250000) {
      for (var k = 0; k < m && k < n; k++) {
        result[gapB[k]] = gapA[k];
      }
      return;
    }
    String paraText(int x) => _units[gapA[x]] is _Para ? (_units[gapA[x]] as _Para).text : '';
    int shared(String a, String t) {
      var p = 0;
      while (p < a.length && p < t.length && a.codeUnitAt(p) == t.codeUnitAt(p)) {
        p++;
      }
      var q = 0;
      while (q < a.length - p && q < t.length - p && a.codeUnitAt(a.length - 1 - q) == t.codeUnitAt(t.length - 1 - q)) {
        q++;
      }
      return p + q;
    }

    // A line shares with a paragraph, with the paragraphs it joined, or
    // with the lines split off after it, what their words have in common
    // at the start and the end.
    int score(int x, int k, int y, int l) => shared(
      <String>[for (var c = x; c < x + k; c++) paraText(c)].join(),
      <String>[for (var c = y; c < y + l; c++) b[gapB[c]].text].join(),
    );
    const most = 3;
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    final pick = List<List<(int, int)>>.generate(n + 1, (_) => List<(int, int)>.filled(m + 1, (0, 0)));
    for (var x = n - 1; x >= 0; x--) {
      for (var y = m - 1; y >= 0; y--) {
        final one = score(x, 1, y, 1);
        var best = table[x + 1][y];
        var choice = (1, 0);
        if (table[x][y + 1] > best) {
          best = table[x][y + 1];
          choice = (0, 1);
        }
        if (one > 0 && one + table[x + 1][y + 1] >= best) {
          best = one + table[x + 1][y + 1];
          choice = (1, 1);
        }
        // A join or a split has to share more than any plainer reading.
        for (var k = 2; k <= most && x + k <= n; k++) {
          final total = score(x, k, y, 1) + table[x + k][y + 1];
          if (total > best) {
            best = total;
            choice = (k, 1);
          }
        }
        for (var l = 2; l <= most && y + l <= m; l++) {
          final total = score(x, 1, y, l) + table[x + 1][y + l];
          if (total > best) {
            best = total;
            choice = (1, l);
          }
        }
        table[x][y] = best;
        pick[x][y] = choice;
      }
    }
    var x = 0, y = 0;
    while (x < n && y < m) {
      final (k, l) = pick[x][y];
      if (k > 0 && l > 0) result[gapB[y]] = gapA[x];
      x += k;
      y += l;
    }
  }

  /// A paragraph written from [line], taking its paragraph properties from
  /// [source] and each character's run properties from the character it
  /// stands for there. A [fresh] line is one typed after [source], which
  /// takes after its last character.
  XmlElement _paragraphFor(
    _Line line,
    _Para? source, {
    required bool fresh,
    _ListRef? before,
    _ListRef? after,
    _Slice? slice,
  }) {
    final p = XmlElement(_w('p'));
    // A line typed after a heading or a quote is plain text, with none of
    // that paragraph's own spacing, breaks or look.
    final plain = fresh &&
        source != null &&
        (source.lineAttributes['header'] != line.attributes['header'] ||
            source.lineAttributes['blockquote'] != line.attributes['blockquote']);
    final props = (plain ? null : source?.pPr?.copy()) ?? XmlElement(_w('pPr'));
    // Section breaks are put back by their own lines.
    props.getElement('w:sectPr')?.remove();
    // A paragraph made from its neighbour is the writer's own, never a
    // reviewer's tracked change.
    if (fresh) {
      props.getElement('w:pPrChange')?.remove();
      final mark = props.getElement('w:rPr');
      if (mark != null) _untrack(mark);
    }
    _applyLine(props, line.attributes, source, before: before, after: after);
    if (props.children.isNotEmpty) p.children.add(props);
    final styleId = props.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
    final lineBase = _baseOf(line.attributes);
    final sameKind = source != null &&
        source.lineAttributes['header'] == line.attributes['header'] &&
        source.lineAttributes['blockquote'] == line.attributes['blockquote'];
    final text = line.text;
    final share = slice ?? (fresh || source == null ? null : _sliceGroup(<String>[text], <_Para>[source]).single);
    final bases = share?.bases ?? _freshBases(text, plain ? null : source);
    final marks = <(int, XmlElement)>[...?share?.marks];
    _sortMarks(marks);
    var nextMark = 0;
    XmlElement? link;
    String? linkTarget;

    void placeMarks(int upTo) {
      while (nextMark < marks.length && marks[nextMark].$1 <= upTo) {
        (link ?? p).children.add(marks[nextMark].$2.copy());
        nextMark++;
      }
    }

    bool markAt(int position) => nextMark < marks.length && marks[nextMark].$1 == position;

    var at = 0;
    for (final op in line.ops) {
      final insert = op['insert'];
      if (insert is Map) {
        placeMarks(at);
        final id = insert[kInlineEmbed];
        final kept = id is String ? inlines[id] : null;
        at++;
        if (kept == null) continue;
        link = null;
        linkTarget = null;
        p.children.addAll(kept.nodes.map((n) => n.copy()));
        continue;
      }
      final chunk = insert! as String;
      final attributes = (op['attributes'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final want = lineBase.withAttributes(attributes);
      var start = 0;
      placeMarks(at);
      for (var i = 1; i <= chunk.length; i++) {
        final ends = i == chunk.length || !_sameRun(bases[at + i - 1], bases[at + i]) || markAt(at + i);
        if (!ends) continue;
        final base = bases[at + start];
        final run = _run(chunk.substring(start, i), base, want, styleId, sameKind, untracked: fresh);
        final target = attributes['link'] as String?;
        if (target == null) {
          link = null;
          linkTarget = null;
          p.children.add(run);
        } else {
          if (link == null || linkTarget != target) {
            link = _hyperlink(target, base.link == target ? base.linkElement : null);
            linkTarget = target;
            p.children.add(link);
          }
          // Words made a link here look like one in Word too.
          if (base.link != target) _styleAsLink(run);
          link.children.add(run);
        }
        start = i;
        if (i < chunk.length) placeMarks(at + start);
      }
      at += chunk.length;
    }
    link = null;
    placeMarks(1 << 30);
    return p;
  }

  /// Takes a reviewer's tracked marks out of run properties copied for new
  /// words.
  static void _untrack(XmlElement rPr) {
    for (final c in rPr.childElements.toList()) {
      if (const <String>{'ins', 'del', 'moveFrom', 'moveTo', 'rPrChange'}.contains(c.name.local)) c.remove();
    }
  }

  /// Gives [run] the document's Hyperlink character style, made when the
  /// document has none.
  void _styleAsLink(XmlElement run) {
    var rPr = run.getElement('w:rPr');
    if (rPr == null) {
      rPr = XmlElement(_w('rPr'));
      run.children.insert(0, rPr);
    }
    if (rPr.getElement('w:rStyle') != null) return;
    rPr.children.insert(0, XmlElement(_w('rStyle'), [XmlAttribute(_w('val'), _linkStyle())]));
  }

  String _linkStyle() {
    for (final style in _styles.values) {
      if (style.type == 'character' && ((style.name ?? '').toLowerCase() == 'hyperlink' || style.id == 'Hyperlink')) {
        return style.id;
      }
    }
    const id = 'Hyperlink';
    final doc = _package.part('word/styles.xml');
    if (doc != null) {
      final element = XmlElement(_w('style'), [
        XmlAttribute(_w('type'), 'character'),
        XmlAttribute(_w('styleId'), id),
      ], [
        XmlElement(_w('name'), [XmlAttribute(_w('val'), 'Hyperlink')]),
        XmlElement(_w('uiPriority'), [XmlAttribute(_w('val'), '99')]),
        XmlElement(_w('unhideWhenUsed')),
        XmlElement(_w('rPr'), [], [
          XmlElement(_w('color'), [XmlAttribute(_w('val'), '0563C1'), XmlAttribute(_w('themeColor'), 'hyperlink')]),
          XmlElement(_w('u'), [XmlAttribute(_w('val'), 'single')]),
        ]),
      ]);
      doc.rootElement.children.add(element);
      _package.touch('word/styles.xml');
      _styles[id] = _Style(id, 'character')
        ..name = 'Hyperlink'
        ..rPr = element.getElement('w:rPr');
    }
    return id;
  }

  /// A line typed with nothing read to stand for, whose characters take
  /// after the last character of [source].
  List<_CharBase> _freshBases(String text, _Para? source) {
    final chars = source?.chars ?? const <_CharBase>[];
    final plain = source?.plain ?? const _CharBase(null, RunLook(), RunLook(), <String, Object?>{}, null);
    _CharBase? near;
    for (var i = chars.length - 1; i >= 0; i--) {
      if (!chars[i].inline) {
        near = chars[i];
        break;
      }
    }
    return List<_CharBase>.filled(text.length, near ?? plain);
  }

  /// The lines [texts] as they share out the paragraphs [olds] they were
  /// made from: each character kept takes its own run, each typed one the
  /// run of the character kept before it, and each mark stands where its
  /// characters went: a start before the first of them kept, an end after
  /// the last, and a range with none kept closed up where it was.
  List<_Slice> _sliceGroup(List<String> texts, List<_Para> olds) {
    final oldText = StringBuffer();
    final oldChars = <_CharBase>[];
    final oldMarks = <(int, XmlElement)>[];
    for (final para in olds) {
      final offset = oldChars.length;
      oldText.write(para.text);
      oldChars.addAll(para.chars);
      for (final (at, mark) in para.marks) {
        oldMarks.add((offset + at, mark));
      }
    }
    final joined = texts.join('\n');
    final kept = alignText(oldText.toString(), joined);
    final plain = olds.first.plain;
    final bases = List<_CharBase?>.filled(joined.length, null);
    for (var k = 0; k < joined.length; k++) {
      final from = kept[k];
      if (from >= 0 && from < oldChars.length && !oldChars[from].inline) bases[k] = oldChars[from];
    }
    _CharBase? near;
    for (var k = 0; k < joined.length; k++) {
      if (kept[k] >= 0 && bases[k] != null) {
        near = bases[k];
      } else {
        bases[k] ??= near;
      }
    }
    _CharBase? after;
    for (var k = joined.length - 1; k >= 0; k--) {
      if (kept[k] >= 0 && bases[k] != null) after = bases[k];
      bases[k] ??= after ?? plain;
    }
    // Where each old character went.
    final newOf = List<int>.filled(oldChars.length, -1);
    for (var k = 0; k < joined.length; k++) {
      if (kept[k] >= 0 && kept[k] < newOf.length) newOf[kept[k]] = k;
    }
    int endAt(int at) {
      for (var o = math.min(at, newOf.length) - 1; o >= 0; o--) {
        if (newOf[o] >= 0) return newOf[o] + 1;
      }
      return 0;
    }

    int startAt(int at) {
      for (var o = at; o < newOf.length; o++) {
        if (newOf[o] >= 0) return newOf[o];
      }
      return joined.length;
    }

    final placed = <(int, XmlElement)>[
      for (final (at, mark) in oldMarks) (_opens(mark) ? startAt(at) : endAt(at), mark),
    ];
    // A range whose characters all went closes up where its end stands.
    final ends = <String, int>{
      for (final (at, mark) in placed)
        if (!_opens(mark)) _rangeKey(mark): at,
    };
    for (var k = 0; k < placed.length; k++) {
      final (at, mark) = placed[k];
      if (!_opens(mark)) continue;
      final end = ends[_rangeKey(mark)];
      if (end != null && end < at) placed[k] = (end, mark);
    }
    final starts = <int>[];
    var at = 0;
    for (final text in texts) {
      starts.add(at);
      at += text.length + 1;
    }
    final out = <_Slice>[];
    for (var i = 0; i < texts.length; i++) {
      final from = starts[i];
      final to = from + texts[i].length;
      out.add(
        _Slice(
          <_CharBase>[for (var k = from; k < to; k++) bases[k]!],
          <(int, XmlElement)>[
            for (final (at, mark) in placed)
              if (at >= from && (at <= to) && (i == texts.length - 1 || at < starts[i + 1]))
                (at - from, mark),
          ],
        ),
      );
    }
    return out;
  }

  static String _rangeKey(XmlElement mark) {
    final local = mark.name.local;
    final kind = local.replaceAll(RegExp(r'(Start|End)$'), '');
    return '$kind:${mark.getAttribute('w:id') ?? ''}';
  }

  XmlElement _run(String text, _CharBase base, RunLook want, String? styleId, bool sameKind, {bool untracked = false}) {
    final r = XmlElement(_w('r'));
    final rPr = base.rPr?.copy() ?? XmlElement(_w('rPr'));
    if (untracked) _untrack(rPr);
    _applyLook(rPr, base, want, styleId, sameKind);
    if (rPr.children.isNotEmpty) r.children.add(rPr);
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      r.children.add(XmlElement(
        _w('t'),
        [XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve')],
        [XmlText(buffer.toString())],
      ));
      buffer.clear();
    }

    for (final unit in text.runes) {
      if (unit == 0x09) {
        flush();
        r.children.add(XmlElement(_w('tab')));
      } else if (unit == 0x2028 || unit == 0x0B) {
        // A vertical tab is the line break of text copied from Word or
        // PowerPoint.
        flush();
        r.children.add(XmlElement(_w('br')));
      } else if (unit >= 0x20 && unit != 0xFFFE && unit != 0xFFFF) {
        // Other control characters cannot be written in XML.
        buffer.writeCharCode(unit);
      }
    }
    flush();
    return r;
  }

  /// Writes into [rPr] what it takes for the run to look as [want] says in
  /// a paragraph of [styleId]: nothing where it already does, the style's
  /// own value by taking direct formatting away, and direct formatting
  /// where the style does not give it. A value the editor could not show,
  /// such as plain text inside a bold heading, is left as the file had it.
  void _applyLook(XmlElement rPr, _CharBase base, RunLook want, String? styleId, bool sameKind) {
    final now = _lookOf(rPr, styleId);
    final styled = _lookOf(
      XmlElement(_w('rPr'), const <XmlAttribute>[], <XmlNode>[
        for (final c in rPr.childElements)
          if (c.name.local == 'rStyle' || c.name.local == 'rtl' || c.name.local == 'cs') c.copy(),
      ]),
      styleId,
    );
    final then = base.shown;
    bool settled<T>(T wanted, T had, T shown) => wanted == had || (sameKind && wanted == shown);

    void flag(String tag, String? complex, bool wanted, bool styledValue) {
      _remove(rPr, tag);
      if (complex != null) _remove(rPr, complex);
      if (wanted == styledValue) return;
      final attributes = wanted ? const <String, String>{} : const <String, String>{'val': '0'};
      _setChild(rPr, tag, attributes, _rPrOrder);
      if (complex != null) _setChild(rPr, complex, attributes, _rPrOrder);
    }

    if (!settled(want.bold, now.bold, then.bold)) flag('b', 'bCs', want.bold, styled.bold);
    if (!settled(want.italic, now.italic, then.italic)) flag('i', 'iCs', want.italic, styled.italic);
    if (!settled(want.strike, now.strike, then.strike)) {
      _remove(rPr, 'dstrike');
      flag('strike', null, want.strike, styled.strike);
    }
    if (!settled(want.underline, now.underline, then.underline)) {
      _remove(rPr, 'u');
      if (want.underline != styled.underline) {
        _setChild(rPr, 'u', {'val': want.underline ? 'single' : 'none'}, _rPrOrder);
      }
    }
    if (!settled(want.color ?? 0, now.color ?? 0, then.color ?? 0)) {
      _remove(rPr, 'color');
      if ((want.color ?? 0) != (styled.color ?? 0)) {
        _setChild(rPr, 'color', {'val': want.color == null ? 'auto' : _hexOf(want.color!).substring(1)}, _rPrOrder);
      }
    }
    if (!settled(want.background, now.background, then.background)) {
      _remove(rPr, 'highlight');
      _remove(rPr, 'shd');
      final background = want.background;
      if (background != styled.background) {
        if (background == null) {
          _setChild(rPr, 'highlight', {'val': 'none'}, _rPrOrder);
        } else {
          final named = kHighlights.entries.where((e) => e.value == background).firstOrNull;
          if (named != null) {
            _setChild(rPr, 'highlight', {'val': named.key}, _rPrOrder);
          } else {
            _setChild(rPr, 'shd', {'val': 'clear', 'color': 'auto', 'fill': _hexOf(background).substring(1)}, _rPrOrder);
          }
        }
      }
    }
    if (!settled(want.size, now.size, then.size)) {
      _remove(rPr, 'sz');
      _remove(rPr, 'szCs');
      if (want.size != styled.size) {
        final half = (want.size * 2).round().toString();
        _setChild(rPr, 'sz', {'val': half}, _rPrOrder);
        _setChild(rPr, 'szCs', {'val': half}, _rPrOrder);
      }
    }
    if (!settled(want.font, now.font, then.font)) {
      final fonts = rPr.getElement('w:rFonts');
      for (final name in const <String>['ascii', 'hAnsi', 'cs', 'asciiTheme', 'hAnsiTheme', 'cstheme']) {
        fonts?.removeAttribute('w:$name');
      }
      if (want.font != styled.font) {
        var target = fonts;
        if (target == null) {
          target = XmlElement(_w('rFonts'));
          _insertOrdered(rPr, target, _rPrOrder);
        }
        for (final name in const <String>['ascii', 'hAnsi', 'cs']) {
          target.setAttribute('w:$name', want.font);
        }
      } else if (fonts != null && fonts.attributes.isEmpty) {
        fonts.remove();
      }
    }
    if (!settled(want.script, now.script, then.script)) {
      _remove(rPr, 'vertAlign');
      if (want.script != styled.script) {
        _setChild(
          rPr,
          'vertAlign',
          {'val': want.script == 1 ? 'superscript' : (want.script == -1 ? 'subscript' : 'baseline')},
          _rPrOrder,
        );
      }
    }
  }

  static void _remove(XmlElement parent, String local) => parent.getElement('w:$local')?.remove();

  void _applyLine(XmlElement pPr, Map<String, Object?> attributes, _Para? source, {_ListRef? before, _ListRef? after}) {
    final was = source?.lineAttributes ?? const <String, Object?>{};
    final header = (attributes['header'] as num?)?.toInt() ?? 0;
    final quote = attributes['blockquote'] == true;
    if (header != ((was['header'] as num?)?.toInt() ?? 0) || quote != (was['blockquote'] == true)) {
      final id = header > 0
          ? _headingStyle(header)
          : (quote ? _findStyleNamed(const <String>{'quote', 'intense quote'}) : null) ?? _bodyStyle;
      if (id == null || id == _defaultParagraphStyle) {
        pPr.getElement('w:pStyle')?.remove();
      } else {
        _setChild(pPr, 'pStyle', {'val': id}, _pPrOrder);
      }
    }
    final styleId = pPr.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
    final list = attributes['list'] as String?;
    final indent = (attributes['indent'] as num?)?.toInt() ?? 0;
    final (numId, level) = _numberingOf(pPr, styleId);
    final kind = numId == null ? null : _kindOf(numId, level);
    if (list == null) {
      if (numId != null) {
        pPr.getElement('w:numPr')?.remove();
        if (_numberingOf(pPr, styleId).$1 != null) {
          // Numbered by its style: a number of 0 takes it out of the list.
          _insertOrdered(pPr, _numPr(0, '0'), _pPrOrder);
        }
        if (was['list'] != null) pPr.getElement('w:ind')?.remove();
      }
    } else if (kind != list || level != indent) {
      final (wasNum, wasLevel) = source == null ? (null, 0) : _numberingOf(source.pPr, source.styleId);
      final id = (kind == list ? numId : null) ??
          (wasNum != null && _kindOf(wasNum, wasLevel) == list ? wasNum : null) ??
          (before?.kind == list ? before!.numId : null) ??
          (after?.kind == list ? after!.numId : null) ??
          _newNumbering(list);
      pPr.getElement('w:numPr')?.remove();
      _insertOrdered(pPr, _numPr(indent, id), _pPrOrder);
      // The level's own indent, as Word and Docs move an item to it.
      pPr.getElement('w:ind')?.remove();
    }
    if (list == null) {
      final wasIndent = was['list'] == null ? ((was['indent'] as num?)?.toInt() ?? 0) : 0;
      if (indent != wasIndent) {
        if (indent == 0) {
          final ind = pPr.getElement('w:ind');
          if (ind != null) {
            ind.removeAttribute('w:left');
            ind.removeAttribute('w:start');
            if (ind.attributes.isEmpty) ind.remove();
          }
        } else {
          final ind = pPr.getElement('w:ind');
          if (ind != null) {
            ind.removeAttribute('w:start');
            ind.setAttribute('w:left', '${indent * 720}');
          } else {
            _setChild(pPr, 'ind', {'left': '${indent * 720}'}, _pPrOrder);
          }
        }
      }
    }
    final align = attributes['align'] as String?;
    if (align != _alignOf(pPr, styleId)) {
      if (align == _alignOf(null, styleId)) {
        pPr.getElement('w:jc')?.remove();
      } else {
        _setChild(
          pPr,
          'jc',
          {
            'val': switch (align) {
              'center' => 'center',
              'right' => 'right',
              'justify' => 'both',
              _ => 'left',
            },
          },
          _pPrOrder,
        );
      }
    }
  }

  static XmlElement _numPr(int level, String numId) => XmlElement(_w('numPr'), const <XmlAttribute>[], <XmlNode>[
        XmlElement(_w('ilvl'), [XmlAttribute(_w('val'), '$level')]),
        XmlElement(_w('numId'), [XmlAttribute(_w('val'), numId)]),
      ]);

  /// The id of the paragraph style for heading [level], added to the
  /// document's styles when it has none.
  String _headingStyle(int level) {
    final found = _findHeadingStyle(level);
    if (found != null) return found;
    final id = 'Heading$level';
    final doc = _package.part('word/styles.xml');
    if (doc != null) {
      final size = <int, int>{1: 32, 2: 26, 3: 24, 4: 22, 5: 22, 6: 22}[level]!;
      final element = XmlElement(_w('style'), [
        XmlAttribute(_w('type'), 'paragraph'),
        XmlAttribute(_w('styleId'), id),
      ], [
        XmlElement(_w('name'), [XmlAttribute(_w('val'), 'heading $level')]),
        XmlElement(_w('basedOn'), [XmlAttribute(_w('val'), _defaultParagraphStyle ?? 'Normal')]),
        XmlElement(_w('next'), [XmlAttribute(_w('val'), _defaultParagraphStyle ?? 'Normal')]),
        XmlElement(_w('qFormat')),
        XmlElement(_w('pPr'), [], [
          XmlElement(_w('keepNext')),
          XmlElement(_w('spacing'), [XmlAttribute(_w('before'), '240'), XmlAttribute(_w('after'), '60')]),
          XmlElement(_w('outlineLvl'), [XmlAttribute(_w('val'), '${level - 1}')]),
        ]),
        XmlElement(_w('rPr'), [], [
          XmlElement(_w('b')),
          XmlElement(_w('sz'), [XmlAttribute(_w('val'), '$size')]),
          XmlElement(_w('szCs'), [XmlAttribute(_w('val'), '$size')]),
        ]),
      ]);
      doc.rootElement.children.add(element);
      _package.touch('word/styles.xml');
      _styles[id] = _Style(id, 'paragraph')
        ..name = 'heading $level'
        ..basedOn = _defaultParagraphStyle
        ..pPr = element.getElement('w:pPr')
        ..rPr = element.getElement('w:rPr');
    }
    return id;
  }

  /// A new numbered list's levels, as the editor draws them: 1., a., i.
  static const _numberFormats = <String>['decimal', 'lowerLetter', 'lowerRoman'];

  /// A numbering of its own for a new bulleted or numbered list, added to
  /// the document, so no list already in it is joined or renumbered.
  String _newNumbering(String list) {
    final want = list == 'bullet';
    var doc = _package.part('word/numbering.xml');
    if (doc == null) {
      doc = XmlDocument.parse(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="$kWordNs"/>',
      );
      _package.create('word/numbering.xml', doc,
          contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml');
      _package.relate(_part, 'numbering.xml',
          'http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering');
    }
    final root = doc.rootElement;
    var abstractId = 0;
    var numId = 1;
    for (final e in root.childElements) {
      if (e.name.local == 'abstractNum') {
        final v = int.tryParse(e.getAttribute('w:abstractNumId') ?? '') ?? 0;
        if (v >= abstractId) abstractId = v + 1;
      } else if (e.name.local == 'num') {
        final v = int.tryParse(e.getAttribute('w:numId') ?? '') ?? 0;
        if (v >= numId) numId = v + 1;
      }
    }
    const bullets = ['•', '◦', '▪'];
    final abstract = XmlElement(_w('abstractNum'), [XmlAttribute(_w('abstractNumId'), '$abstractId')], [
      XmlElement(_w('multiLevelType'), [XmlAttribute(_w('val'), 'hybridMultilevel')]),
      for (var level = 0; level < 9; level++)
        XmlElement(_w('lvl'), [XmlAttribute(_w('ilvl'), '$level')], [
          XmlElement(_w('start'), [XmlAttribute(_w('val'), '1')]),
          XmlElement(_w('numFmt'), [
            XmlAttribute(_w('val'), want ? 'bullet' : _numberFormats[level % 3]),
          ]),
          XmlElement(_w('lvlText'), [
            XmlAttribute(_w('val'), want ? bullets[level % 3] : '%${level + 1}.'),
          ]),
          XmlElement(_w('lvlJc'), [XmlAttribute(_w('val'), 'left')]),
          XmlElement(_w('pPr'), [], [
            XmlElement(_w('ind'), [
              XmlAttribute(_w('left'), '${720 * (level + 1)}'),
              XmlAttribute(_w('hanging'), '360'),
            ]),
          ]),
        ]),
    ]);
    final firstNum = root.childElements.where((e) => e.name.local == 'num' || e.name.local == 'numIdMacAtCleanup').firstOrNull;
    if (firstNum != null) {
      root.children.insert(root.children.indexOf(firstNum), abstract);
    } else {
      root.children.add(abstract);
    }
    final num = XmlElement(_w('num'), [XmlAttribute(_w('numId'), '$numId')], [
      XmlElement(_w('abstractNumId'), [XmlAttribute(_w('val'), '$abstractId')]),
    ]);
    // After the last w:num, and before w:numIdMacAtCleanup, which the
    // schema puts last.
    final lastNum = root.childElements.where((e) => e.name.local == 'num').lastOrNull;
    final cleanup = root.childElements.where((e) => e.name.local == 'numIdMacAtCleanup').firstOrNull;
    if (lastNum != null) {
      root.children.insert(root.children.indexOf(lastNum) + 1, num);
    } else if (cleanup != null) {
      root.children.insert(root.children.indexOf(cleanup), num);
    } else {
      root.children.add(num);
    }
    _package.touch('word/numbering.xml');
    _numFormats['$numId'] = <int, String>{
      for (var level = 0; level < 9; level++) level: want ? 'bullet' : _numberFormats[level % 3],
    };
    return '$numId';
  }

  /// A hyperlink to [target], keeping what the one it was read from carried
  /// besides, such as its tooltip.
  XmlElement _hyperlink(String target, XmlElement? was) {
    final attributes = <XmlAttribute>[
      for (final a in was?.attributes ?? const <XmlAttribute>[])
        if (a.name.qualified != 'r:id' && a.name.qualified != 'w:anchor') a.copy(),
    ];
    if (target.startsWith('#')) {
      return XmlElement(_w('hyperlink'), [XmlAttribute(_w('anchor'), target.substring(1)), ...attributes]);
    }
    var id = _links.entries.where((e) => e.value == target).map((e) => e.key).firstOrNull;
    if (id == null) {
      id = _package.relate(
        _part,
        target,
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',
        external: true,
      );
      _links[id] = target;
    }
    return XmlElement(_w('hyperlink'), [XmlAttribute(XmlName.parts('id', prefix: 'r'), id), ...attributes]);
  }

  static XmlName _w(String local) => XmlName.parts(local, prefix: 'w');

  static XmlElement _ensure(XmlElement parent, String local, List<String> order) {
    final had = parent.getElement('w:$local');
    if (had != null) return had;
    final made = XmlElement(_w(local));
    if (local == 'pPr') {
      parent.children.insert(0, made);
    } else {
      _insertOrdered(parent, made, order);
    }
    return made;
  }

  static void _setChild(XmlElement parent, String local, Map<String, String> attributes, List<String> order) {
    parent.getElement('w:$local')?.remove();
    _insertOrdered(
      parent,
      XmlElement(_w(local), [
        for (final e in attributes.entries) XmlAttribute(_w(e.key), e.value),
      ]),
      order,
    );
  }

  /// Puts [child] among [parent]'s children where the schema's sequence
  /// [order] says it goes, which Word insists on: after the last child that
  /// comes before it, ahead of anything the order does not know.
  static void _insertOrdered(XmlElement parent, XmlElement child, List<String> order) {
    final rank = order.indexOf(child.name.local);
    if (rank < 0) {
      parent.children.add(child);
      return;
    }
    var at = 0;
    for (var i = 0; i < parent.children.length; i++) {
      final node = parent.children[i];
      if (node is! XmlElement) continue;
      final other = order.indexOf(node.name.local);
      if (other >= 0 && other < rank) at = i + 1;
      if (other > rank) break;
    }
    parent.children.insert(at, child);
  }

  static const List<String> _rPrOrder = <String>[
    'rStyle', 'rFonts', 'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', 'strike',
    'dstrike', 'outline', 'shadow', 'emboss', 'imprint', 'noProof',
    'snapToGrid', 'vanish', 'webHidden', 'color', 'spacing', 'w', 'kern',
    'position', 'sz', 'szCs', 'highlight', 'u', 'effect', 'bdr', 'shd',
    'fitText', 'vertAlign', 'rtl', 'cs', 'em', 'lang', 'eastAsianLayout',
    'specVanish', 'oMath', 'rPrChange',
  ];

  static const List<String> _pPrOrder = <String>[
    'pStyle', 'keepNext', 'keepLines', 'pageBreakBefore', 'framePr',
    'widowControl', 'numPr', 'suppressLineNumbers', 'pBdr', 'shd', 'tabs',
    'suppressAutoHyphens', 'kinsoku', 'wordWrap', 'overflowPunct',
    'topLinePunct', 'autoSpaceDE', 'autoSpaceDN', 'bidi', 'adjustRightInd',
    'snapToGrid', 'spacing', 'ind', 'contextualSpacing', 'mirrorIndents',
    'suppressOverlap', 'jc', 'textDirection', 'textAlignment',
    'textboxTightWrap', 'outlineLvl', 'divId', 'cnfStyle', 'rPr', 'sectPr',
    'pPrChange',
  ];
}

/// Sorts marks by where they stand, keeping the order they were read in
/// among marks at one place.
void _sortMarks(List<(int, XmlElement)> marks) {
  final indexed = <(int, int, XmlElement)>[
    for (var i = 0; i < marks.length; i++) (marks[i].$1, i, marks[i].$2),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  for (var i = 0; i < marks.length; i++) {
    marks[i] = (indexed[i].$1, indexed[i].$3);
  }
}

/// [ops] with every attribute written one way: sizes as plain numbers in
/// text, colours as upper case `#RRGGBB`, flags only when set, so an edited
/// document can be compared with the one that was read.
List<DeltaOp> normalizeOps(List<DeltaOp> ops) => <DeltaOp>[
      for (final op in ops)
        () {
          final attributes = (op['attributes'] as Map?)?.cast<String, Object?>();
          if (attributes == null) return <String, Object?>{'insert': op['insert']};
          final clean = <String, Object?>{};
          for (final e in attributes.entries) {
            final value = e.value;
            if (value == null) continue;
            // Off is said only where the look of the line is on.
            if (value == false && !_flags.contains(e.key)) continue;
            switch (e.key) {
              case 'size':
                final size = _sizeOf(value);
                if (size != null) clean['size'] = _sizeText(size);
              case 'color' || 'background':
                final rgb = _rgbOf(value);
                if (rgb != null) clean[e.key] = _hexOf(rgb);
              case 'header' || 'indent':
                final n = value is num ? value.toInt() : int.tryParse('$value');
                if (n != null && n > 0) clean[e.key] = n;
              case 'align':
                if (value != 'left') clean['align'] = value;
              default:
                clean[e.key] = value;
            }
          }
          return <String, Object?>{
            'insert': op['insert'],
            if (clean.isNotEmpty) 'attributes': clean,
          };
        }(),
    ];

const Set<String> _flags = <String>{'bold', 'italic', 'underline', 'strike'};

/// Word's named highlight colours.
const Map<String, int> kHighlights = <String, int>{
  'yellow': 0xFFFF00,
  'green': 0x00FF00,
  'cyan': 0x00FFFF,
  'magenta': 0xFF00FF,
  'blue': 0x0000FF,
  'red': 0xFF0000,
  'darkBlue': 0x000080,
  'darkCyan': 0x008080,
  'darkGreen': 0x008000,
  'darkMagenta': 0x800080,
  'darkRed': 0x800000,
  'darkYellow': 0x808000,
  'darkGray': 0x808080,
  'lightGray': 0xC0C0C0,
  'black': 0x000000,
  'white': 0xFFFFFF,
};

/// What a `w:sym` character looks like: its code in a symbol font mapped
/// to the letter it draws, or the character itself in any other font.
String _symbol(String? font, int? code) {
  if (code == null) return '◇';
  final c = code >= 0xF000 ? code - 0xF000 : code;
  switch ((font ?? '').toLowerCase()) {
    case 'symbol':
      final mapped = _symbolFont[c];
      if (mapped != null) return String.fromCharCode(mapped);
      return c >= 0x20 && c < 0x7F ? String.fromCharCode(c) : '◇';
    case 'wingdings':
      return String.fromCharCode(_wingdings[c] ?? 0x25C7);
  }
  return c >= 0x20 ? String.fromCharCode(c) : '◇';
}

/// The Symbol font's letters that are not the ASCII ones.
const Map<int, int> _symbolFont = <int, int>{
  0x22: 0x2200, 0x24: 0x2203, 0x27: 0x220B, 0x2A: 0x2217, 0x2D: 0x2212,
  0x40: 0x2245, 0x41: 0x0391, 0x42: 0x0392, 0x43: 0x03A7, 0x44: 0x0394,
  0x45: 0x0395, 0x46: 0x03A6, 0x47: 0x0393, 0x48: 0x0397, 0x49: 0x0399,
  0x4A: 0x03D1, 0x4B: 0x039A, 0x4C: 0x039B, 0x4D: 0x039C, 0x4E: 0x039D,
  0x4F: 0x039F, 0x50: 0x03A0, 0x51: 0x0398, 0x52: 0x03A1, 0x53: 0x03A3,
  0x54: 0x03A4, 0x55: 0x03A5, 0x56: 0x03C2, 0x57: 0x03A9, 0x58: 0x039E,
  0x59: 0x03A8, 0x5A: 0x0396, 0x5C: 0x2234, 0x5E: 0x22A5, 0x61: 0x03B1,
  0x62: 0x03B2, 0x63: 0x03C7, 0x64: 0x03B4, 0x65: 0x03B5, 0x66: 0x03C6,
  0x67: 0x03B3, 0x68: 0x03B7, 0x69: 0x03B9, 0x6A: 0x03D5, 0x6B: 0x03BA,
  0x6C: 0x03BB, 0x6D: 0x03BC, 0x6E: 0x03BD, 0x6F: 0x03BF, 0x70: 0x03C0,
  0x71: 0x03B8, 0x72: 0x03C1, 0x73: 0x03C3, 0x74: 0x03C4, 0x75: 0x03C5,
  0x76: 0x03D6, 0x77: 0x03C9, 0x78: 0x03BE, 0x79: 0x03C8, 0x7A: 0x03B6,
  0x7E: 0x223C, 0xA0: 0x20AC, 0xA1: 0x03D2, 0xA2: 0x2032, 0xA3: 0x2264,
  0xA4: 0x2044, 0xA5: 0x221E, 0xA6: 0x0192, 0xA7: 0x2663, 0xA8: 0x2666,
  0xA9: 0x2665, 0xAA: 0x2660, 0xAB: 0x2194, 0xAC: 0x2190, 0xAD: 0x2191,
  0xAE: 0x2192, 0xAF: 0x2193, 0xB0: 0x00B0, 0xB1: 0x00B1, 0xB2: 0x2033,
  0xB3: 0x2265, 0xB4: 0x00D7, 0xB5: 0x221D, 0xB6: 0x2202, 0xB7: 0x2022,
  0xB8: 0x00F7, 0xB9: 0x2260, 0xBA: 0x2261, 0xBB: 0x2248, 0xBC: 0x2026,
  0xBF: 0x21B5, 0xC0: 0x2135, 0xC1: 0x2111, 0xC2: 0x211C, 0xC3: 0x2118,
  0xC4: 0x2297, 0xC5: 0x2295, 0xC6: 0x2205, 0xC7: 0x2229, 0xC8: 0x222A,
  0xC9: 0x2283, 0xCA: 0x2287, 0xCB: 0x2284, 0xCC: 0x2282, 0xCD: 0x2286,
  0xCE: 0x2208, 0xCF: 0x2209, 0xD0: 0x2220, 0xD1: 0x2207, 0xD2: 0x00AE,
  0xD3: 0x00A9, 0xD4: 0x2122, 0xD5: 0x220F, 0xD6: 0x221A, 0xD7: 0x22C5,
  0xD8: 0x00AC, 0xD9: 0x2227, 0xDA: 0x2228, 0xDB: 0x21D4, 0xDC: 0x21D0,
  0xDD: 0x21D1, 0xDE: 0x21D2, 0xDF: 0x21D3, 0xE0: 0x25CA, 0xE1: 0x2329,
  0xE2: 0x00AE, 0xE3: 0x00A9, 0xE4: 0x2122, 0xE5: 0x2211, 0xF1: 0x232A,
  0xF2: 0x222B,
};

/// The Wingdings characters documents use most.
const Map<int, int> _wingdings = <int, int>{
  0x21: 0x270F, 0x22: 0x2702, 0x28: 0x260E, 0x2A: 0x2709, 0x36: 0x231B,
  0x3F: 0x270D, 0x41: 0x270C, 0x43: 0x1F44D, 0x44: 0x1F44E, 0x46: 0x261E,
  0x4A: 0x263A, 0x4C: 0x2639, 0x4E: 0x2620, 0x51: 0x2708, 0x52: 0x263C,
  0x54: 0x2744, 0x58: 0x2720, 0x5B: 0x262F, 0x6C: 0x25CF, 0x6D: 0x274D,
  0x6E: 0x25A0, 0x6F: 0x25A1, 0x71: 0x2751, 0x72: 0x2752, 0x73: 0x2B27,
  0x74: 0x29EB, 0x75: 0x25C6, 0x76: 0x2756, 0x77: 0x2B25, 0x9F: 0x2022,
  0xA1: 0x25CB, 0xA7: 0x25AA, 0xA8: 0x25FB, 0xAB: 0x2605, 0xD8: 0x27A2,
  0xDF: 0x2190, 0xE0: 0x2192, 0xE1: 0x2191, 0xE2: 0x2193, 0xE8: 0x2794,
  0xEF: 0x21E6, 0xF0: 0x21E8, 0xFB: 0x2718, 0xFC: 0x2714, 0xFD: 0x2612,
  0xFE: 0x2611,
};
