import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'ooxml_patch.dart';

/// One piece of a line: text with its look, or something kept whole.
typedef DeltaOp = Map<String, Object?>;

const String kWordNs = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const String kRelNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// The embed a table, a picture of its own or anything else quire keeps
/// whole takes in the editor, and the one something inline takes.
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
    this.size,
    this.font,
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
  final double? size;
  final String? font;

  /// 1 superscript, -1 subscript.
  final int script;

  /// As attributes on a piece of the editor's text.
  Map<String, Object?> get attributes => <String, Object?>{
        if (bold) 'bold': true,
        if (italic) 'italic': true,
        if (underline) 'underline': true,
        if (strike) 'strike': true,
        if (color != null) 'color': _hexOf(color!),
        if (background != null) 'background': _hexOf(background!),
        if (size != null) 'size': _sizeText(size!),
        if (font != null) 'font': font,
        if (script == 1) 'script': 'super',
        if (script == -1) 'script': 'sub',
      };
}

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

/// Something in a paragraph the editor keeps whole: a picture, a field, a
/// page break, a footnote mark. It is shown, and written back as it was.
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

  /// 'image', 'break', 'text' or 'hidden'.
  final String kind;
}

/// Something at body level the editor keeps whole: a table, a content
/// control, a section of its own.
class KeptBlock {
  KeptBlock(this.id, this.element, this.text, {this.rows = const <List<String>>[]});
  final String id;
  final XmlElement element;
  final String text;

  /// A table's cells as text, for showing it.
  final List<List<String>> rows;
}

/// One style a paragraph can be given from the text-format sheet.
class ParagraphStyleChoice {
  const ParagraphStyleChoice(this.label, this.header);
  final String label;

  /// 0 for normal text, 1 to 6 for headings.
  final int header;
}

class _Style {
  _Style(this.id, this.type);
  final String id;
  final String type;
  String? name;
  String? basedOn;
  XmlElement? rPr;
  XmlElement? pPr;
}

class _CharBase {
  const _CharBase(this.rPr, this.look, this.link);
  final XmlElement? rPr;
  final RunLook look;
  final String? link;
}

/// One paragraph as it was read: its element, and each character's run.
class _Para {
  _Para(this.element);
  final XmlElement element;
  final List<Object> pieces = <Object>[]; // String (text) or KeptInline
  final List<_CharBase> chars = <_CharBase>[];
  final List<XmlElement> startMarks = <XmlElement>[];
  final List<XmlElement> endMarks = <XmlElement>[];
  Map<String, Object?> lineAttributes = const <String, Object?>{};
  XmlElement? get pPr => element.getElement('w:pPr');
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

/// A Word document as lines of text the editor can change, with the look
/// each piece of text has, and the way back into the file.
///
/// Only the paragraphs that change are written again. Every other element of
/// the body, and every other part of the package, is written back exactly as
/// it was read. A changed paragraph keeps its paragraph properties, and each
/// character keeps the run properties it had, with only the formatting the
/// reader changed written on top as direct formatting.
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
  String? _defaultParagraphStyle;
  final Map<String, Map<int, String>> _numFormats = <String, Map<int, String>>{};
  final Map<String, String> _links = <String, String>{};

  late XmlElement _body;
  final List<Object> _units = <Object>[]; // _Para or KeptBlock
  final List<List<XmlElement>> _before = <List<XmlElement>>[];
  XmlElement? _sectPr;
  final Map<String, KeptInline> inlines = <String, KeptInline>{};
  final Map<String, KeptBlock> blocks = <String, KeptBlock>{};
  late final List<_Line> _lines;

  /// The document as the editor starts from it.
  late final List<DeltaOp> ops;

  /// The bytes of a picture in the package.
  Uint8List? partBytes(String name) => _package.bytesOf(name);

  /// The paragraph styles the text-format sheet offers.
  List<ParagraphStyleChoice> get styleChoices => <ParagraphStyleChoice>[
        const ParagraphStyleChoice('Normal text', 0),
        for (var level = 1; level <= 3; level++)
          ParagraphStyleChoice('Heading $level', level),
      ];

  // Reading.

  void _read() {
    final doc = _package.part(_part);
    if (doc == null) throw const FormatException('no word/document.xml');
    final body = doc.rootElement.getElement('w:body');
    if (body == null) throw const FormatException('no document body');
    _body = body;
    _loadStyles();
    _loadNumbering();
    _links.addAll(_package.relationships(_part));
    var pending = <XmlElement>[];
    var n = 0;
    for (final child in body.childElements) {
      final local = child.name.local;
      if (local == 'sectPr') {
        _sectPr = child;
        continue;
      }
      if (local == 'p') {
        _units.add(_paragraph(child));
      } else if (_invisible.contains(local)) {
        pending.add(child);
        continue;
      } else {
        final id = 'b${n++}';
        final kept = KeptBlock(id, child, child.innerText.trim(), rows: _tableRows(child));
        blocks[id] = kept;
        _units.add(kept);
      }
      _before.add(pending);
      pending = <XmlElement>[];
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

  List<XmlElement> _trailing = const <XmlElement>[];

  static const _invisible = <String>{
    'bookmarkStart', 'bookmarkEnd', 'proofErr', 'permStart', 'permEnd',
    'commentRangeStart', 'commentRangeEnd', 'moveFromRangeStart',
    'moveFromRangeEnd', 'moveToRangeStart', 'moveToRangeEnd',
  };

  static List<List<String>> _tableRows(XmlElement element) {
    if (element.name.local != 'tbl') return const <List<String>>[];
    return <List<String>>[
      for (final tr in element.childElements.where((e) => e.name.local == 'tr'))
        <String>[
          for (final tc in tr.childElements.where((e) => e.name.local == 'tc'))
            tc.childElements
                .where((e) => e.name.local == 'p')
                .map((p) => p.descendantElements
                    .where((e) => e.name.local == 't')
                    .map((t) => t.innerText)
                    .join())
                .join('\n'),
        ],
    ];
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
        final ends = i == text.length ||
            !_sameBase(para.chars[at + i - 1], para.chars[at + i]);
        if (!ends) continue;
        final chunk = text.substring(start, i);
        final base = para.chars[at + start];
        ops.add(<String, Object?>{
          'insert': chunk,
          if (_attributesOf(base).isNotEmpty) 'attributes': _attributesOf(base),
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
        ...base.look.attributes,
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

  _Para _paragraph(XmlElement p) {
    final para = _Para(p);
    final pPr = p.getElement('w:pPr');
    final styleId = pPr?.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
    para.lineAttributes = _lineAttributesOf(pPr, styleId);
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
      para.chars.add(const _CharBase(null, RunLook(), null));
    }

    void addRun(XmlElement r, String? link) {
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
      final look = _lookOf(rPr, pPr);
      final hidden = rPr?.getElement('w:vanish') != null;
      final drawing = r.childElements.where((c) {
        final local = c.name.local;
        return local == 'drawing' || local == 'pict' || local == 'object';
      }).firstOrNull;
      final special = r.childElements.where((c) {
        final local = c.name.local;
        return local == 'footnoteReference' ||
            local == 'endnoteReference' ||
            local == 'commentReference' ||
            (local == 'br' && (c.getAttribute('w:type') == 'page' || c.getAttribute('w:type') == 'column'));
      }).firstOrNull;
      if (hidden || drawing != null || special != null) {
        final (part, w, h) = drawing == null ? (null, null, null) : _pictureOf(drawing);
        keep(KeptInline(
          'i${inlines.length}',
          <XmlNode>[r],
          r.innerText,
          imagePart: part,
          width: w,
          height: h,
          kind: hidden
              ? 'hidden'
              : drawing != null
                  ? 'image'
                  : (special!.name.local == 'br' ? 'break' : 'text'),
        ));
        return;
      }
      for (final c in r.childElements) {
        final String? chunk = switch (c.name.local) {
          't' => c.innerText,
          'tab' || 'ptab' => '\t',
          'br' || 'cr' => kSoftBreak,
          'noBreakHyphen' => '‑',
          'softHyphen' => '­',
          'sym' => () {
              final code = int.tryParse(c.getAttribute('w:char') ?? '', radix: 16);
              return code == null ? null : String.fromCharCode(code >= 0xF000 ? code - 0xF000 : code);
            }(),
          _ => null,
        };
        if (chunk == null || chunk.isEmpty) continue;
        text.write(chunk);
        for (var i = 0; i < chunk.length; i++) {
          para.chars.add(_CharBase(rPr, look, link));
        }
      }
    }

    void walk(XmlElement e, String? link) {
      for (final c in e.childElements) {
        final local = c.name.local;
        switch (local) {
          case 'pPr':
            break;
          case 'r':
            addRun(c, link);
          case 'hyperlink':
            final rid = c.getAttribute('r:id') ?? c.getAttribute('id', namespaceUri: kRelNs);
            final anchor = c.getAttribute('w:anchor');
            final target = rid != null ? _links[rid] : null;
            walk(c, target ?? (anchor != null ? '#$anchor' : link));
          case 'ins' || 'smartTag' || 'customXml' || 'dir' || 'bdo':
            walk(c, link);
          case 'bookmarkStart' || 'commentRangeStart' || 'permStart' || 'moveFromRangeStart' || 'moveToRangeStart':
            if (fieldDepth > 0) {
              field.add(c);
            } else {
              para.startMarks.add(c);
            }
          case 'bookmarkEnd' || 'commentRangeEnd' || 'permEnd' || 'moveFromRangeEnd' || 'moveToRangeEnd':
            if (fieldDepth > 0) {
              field.add(c);
            } else {
              para.endMarks.add(c);
            }
          case 'proofErr':
            break;
          default:
            if (fieldDepth > 0) {
              field.add(c);
              continue;
            }
            // A simple field, a content control, a deletion, maths: kept
            // whole and shown by what it reads.
            keep(KeptInline(
              'i${inlines.length}',
              <XmlNode>[c],
              local == 'del' ? '' : c.innerText,
              kind: local == 'del' ? 'hidden' : 'text',
            ));
        }
      }
    }

    walk(p, null);
    flushText();
    return para;
  }

  (String?, double?, double?) _pictureOf(XmlElement drawing) {
    String? rid;
    double? w, h;
    for (final e in drawing.descendantElements) {
      final local = e.name.local;
      if (local == 'blip' || local == 'imagedata') {
        rid ??= e.getAttribute('r:embed') ?? e.getAttribute('r:id') ?? e.getAttribute('embed', namespaceUri: kRelNs);
      } else if (local == 'extent') {
        final cx = double.tryParse(e.getAttribute('cx') ?? '');
        final cy = double.tryParse(e.getAttribute('cy') ?? '');
        if (cx != null) w = cx / 12700;
        if (cy != null) h = cy / 12700;
      }
    }
    return (rid == null ? null : _links[rid], w, h);
  }

  Map<String, Object?> _lineAttributesOf(XmlElement? pPr, String? styleId) {
    final out = <String, Object?>{};
    final level = _headingOf(styleId);
    if (level != null && level >= 1 && level <= 6) out['header'] = level;
    final numPr = pPr?.getElement('w:numPr') ?? _styleNumPr(styleId);
    final numId = numPr?.getElement('w:numId')?.getAttribute('w:val');
    final ilvl = int.tryParse(numPr?.getElement('w:ilvl')?.getAttribute('w:val') ?? '0') ?? 0;
    if (numId != null && numId != '0' && _numFormats.containsKey(numId)) {
      final format = _numFormats[numId]![ilvl] ?? _numFormats[numId]![0] ?? 'bullet';
      out['list'] = format == 'bullet' || format == 'none' ? 'bullet' : 'ordered';
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

  /// The look a run has once its paragraph's style, its own character style
  /// and its direct formatting are laid over the document's defaults.
  RunLook _lookOf(XmlElement? rPr, XmlElement? pPr) {
    final layers = <XmlElement>[];
    if (_defaultRPr != null) layers.add(_defaultRPr!);
    final pStyle = pPr?.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
    layers.addAll(_styleChain(pStyle));
    final rStyle = rPr?.getElement('w:rStyle')?.getAttribute('w:val');
    layers.addAll(_styleChain(rStyle));
    if (rPr != null) layers.add(rPr);
    var bold = false, italic = false, underline = false, strike = false;
    int? color, background;
    double? size;
    String? font;
    var script = 0;
    for (final layer in layers) {
      bool? flag(String tag) {
        final e = layer.getElement('w:$tag');
        if (e == null) return null;
        final v = e.getAttribute('w:val');
        return v == null || v == '1' || v == 'true' || v == 'on';
      }

      bold = flag('b') ?? bold;
      italic = flag('i') ?? italic;
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
      final sz = double.tryParse(layer.getElement('w:sz')?.getAttribute('w:val') ?? '');
      if (sz != null) size = sz / 2;
      final fonts = layer.getElement('w:rFonts');
      final ascii = fonts?.getAttribute('w:ascii') ?? fonts?.getAttribute('w:hAnsi');
      if (ascii != null) font = ascii;
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
      size: size,
      font: font,
      script: script,
    );
  }

  /// A style's rPr and the rPrs of the styles it is based on, the furthest
  /// first so the nearest wins.
  List<XmlElement> _styleChain(String? styleId) {
    final chain = <XmlElement>[];
    var id = styleId;
    var guard = 0;
    while (id != null && guard++ < 12) {
      final style = _styles[id];
      if (style == null) break;
      if (style.rPr != null) chain.insert(0, style.rPr!);
      id = style.basedOn;
    }
    return chain;
  }

  void _loadStyles() {
    final doc = _package.part('word/styles.xml');
    if (doc == null) return;
    final root = doc.rootElement;
    _defaultRPr = root.getElement('w:docDefaults')?.getElement('w:rPrDefault')?.getElement('w:rPr');
    for (final s in root.childElements.where((e) => e.name.local == 'style')) {
      final id = s.getAttribute('w:styleId');
      if (id == null) continue;
      final style = _Style(id, s.getAttribute('w:type') ?? 'paragraph')
        ..name = s.getElement('w:name')?.getAttribute('w:val')
        ..basedOn = s.getElement('w:basedOn')?.getAttribute('w:val')
        ..rPr = s.getElement('w:rPr')
        ..pPr = s.getElement('w:pPr');
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
    final out = <XmlNode>[];
    _Para? lastSource;
    XmlElement? lastWritten;
    final used = <int>{};
    final droppedSections = <XmlElement>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final source = matches[i];
      final blockId = line.blockId;
      if (blockId != null) {
        final index = _units.indexWhere((u) => u is KeptBlock && u.id == blockId);
        if (index < 0 || used.contains(index)) continue;
        used.add(index);
        out
          ..addAll(_before[index].map((e) => e.copy()))
          ..add(blocks[blockId]!.element.copy());
        continue;
      }
      final unit = source == null ? null : _units[source];
      final para = unit is _Para ? unit : null;
      final first = source != null && used.add(source);
      if (source != null && first) out.addAll(_before[source].map((e) => e.copy()));
      if (para != null && first && line.key == _lines[source].key) {
        final kept = para.element.copy();
        out.add(kept);
        lastWritten = kept;
        lastSource = para;
        continue;
      }
      final written = _paragraphFor(line, para ?? lastSource, reuseMarks: first && para != null);
      out.add(written);
      lastWritten = written;
      if (para != null) lastSource = para;
    }
    // A section break lives in the last paragraph of its section; a deleted
    // paragraph's break is given to the paragraph before it, so the section
    // and its headers and footers survive.
    for (var i = 0; i < _units.length; i++) {
      final unit = _units[i];
      if (used.contains(i) || unit is! _Para) continue;
      final sect = unit.pPr?.getElement('w:sectPr');
      if (sect != null) droppedSections.add(sect);
    }
    if (droppedSections.isNotEmpty && lastWritten != null) {
      final pPr = _ensure(lastWritten, 'pPr', _pPrOrder);
      if (pPr.getElement('w:sectPr') == null) {
        _insertOrdered(pPr, droppedSections.last.copy(), _pPrOrder);
      }
    }
    for (final mark in _trailing) {
      out.add(mark.copy());
    }
    final sect = _sectPr;
    if (sect != null) out.add(sect.copy());
    _body.children
      ..clear()
      ..addAll(out);
    _package.touch(_part);
    return _package.write();
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
          lines.add(_Line(_merged(_clean(current)), _blockOnly(attributes)));
          current = <DeltaOp>[];
          rest = rest.substring(at + 1);
        }
      } else if (insert is Map) {
        current.add(<String, Object?>{'insert': Map<String, Object?>.of(insert.cast<String, Object?>())});
      }
    }
    if (current.isNotEmpty) lines.add(_Line(_merged(_clean(current)), const <String, Object?>{}));
    return lines;
  }

  static const _blockKeys = <String>{'header', 'list', 'indent', 'align'};

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
    final a = _lines, b = lines;
    var start = 0;
    while (start < a.length && start < b.length && a[start].key == b[start].key) {
      result[start] = start;
      start++;
    }
    var endA = a.length, endB = b.length;
    while (endA > start && endB > start && a[endA - 1].key == b[endB - 1].key) {
      endA--;
      endB--;
      result[endB] = endA;
    }
    final n = endA - start, m = endB - start;
    if (n == 0 || m == 0) {
      if (n > 0 && m > 0) return result;
      // Only insertions or only deletions: new lines take after the line
      // before them.
      for (var j = start; j < endB; j++) {
        result[j] = null;
      }
      return result;
    }
    if (n * m > 4000000) {
      for (var j = 0; j < m; j++) {
        result[start + j] = j < n ? start + j : null;
      }
      return result;
    }
    // Longest common run of unchanged lines in the middle.
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = a[start + i].key == b[start + j].key
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] > table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    final gapA = <int>[], gapB = <int>[];
    void pairGap() {
      for (var k = 0; k < gapB.length; k++) {
        result[gapB[k]] = k < gapA.length ? gapA[k] : null;
      }
      gapA.clear();
      gapB.clear();
    }

    while (i < n && j < m) {
      if (a[start + i].key == b[start + j].key) {
        pairGap();
        result[start + j] = start + i;
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        gapA.add(start + i);
        i++;
      } else {
        gapB.add(start + j);
        j++;
      }
    }
    while (i < n) {
      gapA.add(start + i++);
    }
    while (j < m) {
      gapB.add(start + j++);
    }
    pairGap();
    return result;
  }

  /// A paragraph written from [line], taking its paragraph properties from
  /// [source] and each character's run properties from the character it
  /// stands for there.
  XmlElement _paragraphFor(_Line line, _Para? source, {required bool reuseMarks}) {
    final p = XmlElement(_w('p'));
    final pPr = source?.pPr?.copy();
    final props = pPr ?? XmlElement(_w('pPr'));
    // A paragraph taking after another does not also take its section
    // break or the marks that belong to that paragraph.
    if (!reuseMarks) props.getElement('w:sectPr')?.remove();
    _applyLine(props, line.attributes, source);
    if (props.children.isNotEmpty) p.children.add(props);
    if (reuseMarks && source != null) {
      p.children.addAll(source.startMarks.map((e) => e.copy()));
    }
    final bases = _basesFor(line, source);
    var at = 0;
    XmlElement? link;
    String? linkTarget;
    for (final op in line.ops) {
      final insert = op['insert'];
      if (insert is Map) {
        final id = insert[kInlineEmbed];
        final kept = id is String ? inlines[id] : null;
        at++;
        if (kept == null) continue;
        link = null;
        linkTarget = null;
        p.children.addAll(kept.nodes.map((n) => n.copy()));
        continue;
      }
      final text = insert! as String;
      final attributes = (op['attributes'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      var start = 0;
      for (var i = 1; i <= text.length; i++) {
        final ends = i == text.length || !_sameRun(bases[at + i - 1], bases[at + i]);
        if (!ends) continue;
        final base = bases[at + start];
        final run = _run(text.substring(start, i), base, attributes);
        final target = attributes['link'] as String?;
        if (target == null) {
          link = null;
          linkTarget = null;
          p.children.add(run);
        } else {
          if (link == null || linkTarget != target) {
            link = _hyperlink(target);
            linkTarget = target;
            p.children.add(link);
          }
          link.children.add(run);
        }
        start = i;
      }
      at += text.length;
    }
    if (reuseMarks && source != null) {
      p.children.addAll(source.endMarks.map((e) => e.copy()));
    }
    return p;
  }

  /// Each character of [line] paired with the character of [source] it came
  /// from: the ones before and after the change as they were, and new ones
  /// taking after the character they were typed next to.
  List<_CharBase> _basesFor(_Line line, _Para? source) {
    final text = line.text;
    final original = StringBuffer();
    if (source != null) {
      for (final piece in source.pieces) {
        original.write(piece is String ? piece : '￼');
      }
    }
    final old = original.toString();
    final chars = source?.chars ?? const <_CharBase>[];
    const plain = _CharBase(null, RunLook(), null);
    if (chars.isEmpty || old.isEmpty) return List<_CharBase>.filled(text.length, plain);
    var prefix = 0;
    while (prefix < old.length && prefix < text.length && old.codeUnitAt(prefix) == text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < old.length - prefix &&
        suffix < text.length - prefix &&
        old.codeUnitAt(old.length - 1 - suffix) == text.codeUnitAt(text.length - 1 - suffix)) {
      suffix++;
    }
    final out = <_CharBase>[];
    for (var i = 0; i < text.length; i++) {
      if (i < prefix) {
        out.add(chars[i]);
      } else if (i >= text.length - suffix) {
        out.add(chars[old.length - (text.length - i)]);
      } else {
        final near = prefix > 0 ? prefix - 1 : (prefix < chars.length ? prefix : chars.length - 1);
        out.add(chars[near]);
      }
    }
    return out;
  }

  XmlElement _run(String text, _CharBase base, Map<String, Object?> attributes) {
    final r = XmlElement(_w('r'));
    final rPr = base.rPr?.copy() ?? XmlElement(_w('rPr'));
    _applyLook(rPr, base.look, attributes);
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
      } else if (unit == 0x2028) {
        flush();
        r.children.add(XmlElement(_w('br')));
      } else {
        buffer.writeCharCode(unit);
      }
    }
    flush();
    return r;
  }

  /// Writes into [rPr] the formatting [attributes] give that [look], what
  /// the character already had, does not.
  void _applyLook(XmlElement rPr, RunLook look, Map<String, Object?> attributes) {
    void flag(String tag, bool want, bool had) {
      if (want == had) return;
      _setChild(rPr, tag, want ? const <String, String>{} : const <String, String>{'val': '0'}, _rPrOrder);
    }

    flag('b', attributes['bold'] == true, look.bold);
    flag('i', attributes['italic'] == true, look.italic);
    flag('strike', attributes['strike'] == true, look.strike);
    final underline = attributes['underline'] == true;
    if (underline != look.underline) {
      _setChild(rPr, 'u', {'val': underline ? 'single' : 'none'}, _rPrOrder);
    }
    final color = _rgbOf(attributes['color']);
    if (color != look.color) {
      _setChild(
        rPr,
        'color',
        {'val': color == null ? 'auto' : _hexOf(color).substring(1)},
        _rPrOrder,
      );
    }
    final background = _rgbOf(attributes['background']);
    if (background != look.background) {
      rPr.getElement('w:highlight')?.remove();
      rPr.getElement('w:shd')?.remove();
      if (background != null) {
        final named = kHighlights.entries.where((e) => e.value == background).firstOrNull;
        if (named != null) {
          _setChild(rPr, 'highlight', {'val': named.key}, _rPrOrder);
        } else {
          _setChild(rPr, 'shd', {'val': 'clear', 'color': 'auto', 'fill': _hexOf(background).substring(1)}, _rPrOrder);
        }
      } else if (look.background != null) {
        _setChild(rPr, 'highlight', {'val': 'none'}, _rPrOrder);
      }
    }
    final size = _sizeOf(attributes['size']);
    if (size != null && size != look.size) {
      final half = (size * 2).round().toString();
      _setChild(rPr, 'sz', {'val': half}, _rPrOrder);
      _setChild(rPr, 'szCs', {'val': half}, _rPrOrder);
    }
    final font = attributes['font'] as String?;
    if (font != null && font != look.font) {
      _setChild(rPr, 'rFonts', {'ascii': font, 'hAnsi': font, 'cs': font}, _rPrOrder);
    }
    final script = switch (attributes['script']) {
      'super' => 1,
      'sub' => -1,
      _ => 0,
    };
    if (script != look.script) {
      _setChild(
        rPr,
        'vertAlign',
        {'val': script == 1 ? 'superscript' : (script == -1 ? 'subscript' : 'baseline')},
        _rPrOrder,
      );
    }
  }

  void _applyLine(XmlElement pPr, Map<String, Object?> attributes, _Para? source) {
    final before = source?.lineAttributes ?? const <String, Object?>{};
    final header = attributes['header'] as int?;
    if (header != before['header']) {
      if (header == null || header == 0) {
        pPr.getElement('w:pStyle')?.remove();
      } else {
        _setChild(pPr, 'pStyle', {'val': _headingStyle(header)}, _pPrOrder);
      }
    }
    final list = attributes['list'] as String?;
    final indent = (attributes['indent'] as num?)?.toInt() ?? 0;
    if (list != before['list'] || (list != null && indent != ((before['indent'] as num?)?.toInt() ?? 0))) {
      if (list == null) {
        pPr.getElement('w:numPr')?.remove();
        if (before['list'] != null) {
          // Out of the list, the paragraph also gives up the indent the
          // list gave it.
          pPr.getElement('w:ind')?.remove();
        }
      } else {
        final numId = before['list'] == list
            ? (pPr.getElement('w:numPr')?.getElement('w:numId')?.getAttribute('w:val') ?? _numberingFor(list))
            : _numberingFor(list);
        pPr.getElement('w:numPr')?.remove();
        _insertOrdered(
          pPr,
          XmlElement(_w('numPr'), [], [
            XmlElement(_w('ilvl'), [XmlAttribute(_w('val'), '$indent')]),
            XmlElement(_w('numId'), [XmlAttribute(_w('val'), numId)]),
          ]),
          _pPrOrder,
        );
      }
    } else if (list == null && indent != ((before['indent'] as num?)?.toInt() ?? 0)) {
      if (indent == 0) {
        pPr.getElement('w:ind')?.remove();
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
    final align = attributes['align'] as String?;
    if (align != before['align']) {
      final styleId = pPr.getElement('w:pStyle')?.getAttribute('w:val') ?? _defaultParagraphStyle;
      final styleAlign = _alignOf(null, styleId);
      if (align == styleAlign) {
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

  /// The id of the paragraph style for heading [level], added to the
  /// document's styles when it has none.
  String _headingStyle(int level) {
    for (final style in _styles.values) {
      if (style.type != 'paragraph') continue;
      final outline = int.tryParse(style.pPr?.getElement('w:outlineLvl')?.getAttribute('w:val') ?? '');
      final name = (style.name ?? '').toLowerCase();
      if (outline == level - 1 || name == 'heading $level') return style.id;
    }
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
        ..pPr = element.getElement('w:pPr')
        ..rPr = element.getElement('w:rPr');
    }
    return id;
  }

  /// A numbering id for a bulleted or numbered list: one the document
  /// already uses when it has one, or one added to it.
  String _numberingFor(String list) {
    final want = list == 'bullet';
    for (final entry in _numFormats.entries) {
      final format = entry.value[0] ?? 'bullet';
      if ((format == 'bullet') == want) return entry.key;
    }
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
            XmlAttribute(_w('val'), want ? 'bullet' : (level.isEven ? 'decimal' : 'lowerLetter')),
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
    final firstNum = root.childElements.where((e) => e.name.local == 'num').firstOrNull;
    if (firstNum != null) {
      root.children.insert(root.children.indexOf(firstNum), abstract);
    } else {
      root.children.add(abstract);
    }
    root.children.add(XmlElement(_w('num'), [XmlAttribute(_w('numId'), '$numId')], [
      XmlElement(_w('abstractNumId'), [XmlAttribute(_w('val'), '$abstractId')]),
    ]));
    _package.touch('word/numbering.xml');
    _numFormats['$numId'] = <int, String>{
      for (var level = 0; level < 9; level++) level: want ? 'bullet' : 'decimal',
    };
    return '$numId';
  }

  XmlElement _hyperlink(String target) {
    if (target.startsWith('#')) {
      return XmlElement(_w('hyperlink'), [XmlAttribute(_w('anchor'), target.substring(1))]);
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
    return XmlElement(_w('hyperlink'), [XmlAttribute(XmlName.parts('id', prefix: 'r'), id)]);
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
  /// [order] says it goes, which Word insists on.
  static void _insertOrdered(XmlElement parent, XmlElement child, List<String> order) {
    final rank = order.indexOf(child.name.local);
    if (rank < 0) {
      parent.children.add(child);
      return;
    }
    for (var i = 0; i < parent.children.length; i++) {
      final node = parent.children[i];
      if (node is! XmlElement) continue;
      final other = order.indexOf(node.name.local);
      if (other > rank) {
        parent.children.insert(i, child);
        return;
      }
    }
    parent.children.add(child);
  }

  static const List<String> _rPrOrder = <String>[
    'rStyle', 'rFonts', 'b', 'bCs', 'i', 'iCs', 'caps', 'smallCaps', 'strike',
    'dstrike', 'outline', 'shadow', 'emboss', 'imprint', 'noProof',
    'snapToGrid', 'vanish', 'webHidden', 'color', 'spacing', 'w', 'kern',
    'position', 'sz', 'szCs', 'highlight', 'u', 'effect', 'bdr', 'shd',
    'fitText', 'vertAlign', 'rtl', 'cs', 'em', 'lang', 'eastAsianLayout',
    'specVanish', 'oMath',
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
            if (value == null || value == false) continue;
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
