import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../format/pptx_parser.dart';
import '../model/document.dart';
import 'zip_patch.dart';

const String kNsP = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const String kNsA = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String kNsR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _relSlide = '$_rel/slide';
const String _relLayout = '$_rel/slideLayout';
const String _relImage = '$_rel/image';
const String _relNotes = '$_rel/notesSlide';
const String _typeSlide = 'application/vnd.openxmlformats-officedocument.presentationml.slide+xml';
const String _typeNotes = 'application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml';
const String _deck = 'ppt/presentation.xml';
const String _types = '[Content_Types].xml';

/// Relationship types whose target belongs to the one part pointing at it,
/// so a copy of that part needs a copy of the target too.
const Set<String> _privateTargets = <String>{
  'comments',
  'chart',
  'chartUserShapes',
  'diagramData',
  'diagramLayout',
  'diagramQuickStyle',
  'diagramColors',
  'diagramDrawing',
  'package',
  'oleObject',
  'tags',
};

int _emu(double points) => (points * kEmuPerPoint).round();

/// One relationship as a part states it.
class DeckRel {
  const DeckRel(this.id, this.type, this.target, {this.external = false});
  final String id;
  final String type;

  /// For an internal relationship, the part's path inside the package.
  final String target;
  final bool external;

  String get kind => type.substring(type.lastIndexOf('/') + 1);
}

/// Shapes taken off a slide by Cut or Copy, with what they point at.
class SlideClip {
  const SlideClip(this.from, this.elements, this.rels, this.boxes);
  final String from;
  final List<XmlElement> elements;
  final Map<String, DeckRel> rels;
  final List<SlideBox> boxes;
}

/// Slides taken out of the deck by Cut or Copy.
class SlidesClip {
  const SlidesClip(this.slides);
  final List<KeptSlide> slides;
  int get length => slides.length;
}

/// One slide as Cut or Copy kept it: its part, its relationships and its
/// notes.
class KeptSlide {
  const KeptSlide(this.xml, this.rels, this.notes, this.notesRels);
  final String xml;
  final List<DeckRel> rels;
  final String? notes;
  final List<DeckRel> notesRels;
}

/// Which way an object moves through the stack of things on its slide.
enum SlideOrder { front, forward, backward, back }

class _State {
  _State(this.texts, this.bytes, this.gone);
  final Map<String, String> texts;
  final Map<String, Uint8List> bytes;
  final Set<String> gone;

  _State copy() => _State(
    Map<String, String>.of(texts),
    Map<String, Uint8List>.of(bytes),
    Set<String>.of(gone),
  );
}

/// A PowerPoint deck opened for editing on the slide.
///
/// Everything is done to the parts themselves: a shape is moved by its own
/// transform, a slide is added from the deck's own layout, a theme is the
/// deck's theme part with new colours in it. Every change is one step that
/// Undo takes back, and only the parts that changed are written; every
/// other part of the file is copied across byte for byte.
class PptxDeck {
  PptxDeck(this.original) : _zip = ZipDecoder().decodeBytes(original) {
    if (_textOf(_deck) == null) throw const FormatException('no ppt/presentation.xml');
    if (slides.isEmpty) throw const FormatException('a deck with no slides');
  }

  final Uint8List original;
  final Archive _zip;
  _State _now = _State(<String, String>{}, <String, Uint8List>{}, <String>{});
  final List<(_State, String)> _undo = <(_State, String)>[];
  final List<(_State, String)> _redo = <(_State, String)>[];
  int _version = 0;

  PptxParser? _parser;
  List<String>? _slides;
  List<SlideLayoutInfo>? _layouts;
  Map<String, Uint8List>? _zipMedia;
  final Map<String, SlideBlock> _drawn = <String, SlideBlock>{};
  final Map<String, List<SlideObject>> _objects = <String, List<SlideObject>>{};
  final Map<String, SlideBlock> _layoutDrawn = <String, SlideBlock>{};

  /// Goes up by one with every change, undo and redo.
  int get version => _version;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// How many steps a save would keep.
  int get steps => _undo.length;

  bool get changed => _now.texts.isNotEmpty || _now.bytes.isNotEmpty || _now.gone.isNotEmpty;

  // Reading.

  String? _textOf(String name) {
    if (_now.gone.contains(name)) return null;
    final held = _now.texts[name];
    if (held != null) return held;
    final file = _zip.find(name);
    if (file == null) return null;
    return utf8.decode(file.content, allowMalformed: true);
  }

  XmlDocument? _doc(String name) {
    final text = _textOf(name);
    if (text == null) return null;
    try {
      return XmlDocument.parse(text);
    } on XmlException {
      return null;
    }
  }

  void _put(String name, XmlDocument doc) {
    _now.texts[name] = doc.toXmlString();
    _now.gone.remove(name);
  }

  bool _exists(String name) =>
      _now.texts.containsKey(name) ||
      _now.bytes.containsKey(name) ||
      _now.gone.contains(name) ||
      _zip.find(name) != null;

  Map<String, Uint8List> get _media => _zipMedia ??= <String, Uint8List>{
    for (final file in _zip.files)
      if (file.isFile && file.name.startsWith('ppt/media/')) file.name: file.content,
  };

  /// Every picture the deck holds, by path.
  Map<String, Uint8List> get assets => <String, Uint8List>{..._media, ..._now.bytes};

  PptxParser get _reader => _parser ??= PptxParser(
    original,
    archive: _zip,
    parts: (path) => _now.gone.contains(path) ? '' : _now.texts[path],
    media: assets,
    loadMedia: false,
  );

  /// The deck's slides, by part, in the order it shows them.
  List<String> get slides => _slides ??= _reader.slideParts();

  /// The slide at [path], drawn as the reader draws it.
  SlideBlock slide(String path) =>
      _drawn[path] ??= _reader.slideAt(path, index: slides.indexOf(path));

  /// What on the slide at [path] can be picked up.
  List<SlideObject> objects(String path) => _objects[path] ??= _reader.objectsAt(path);

  SlideObject? object(String path, int id) {
    for (final o in objects(path)) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// The drawn shape that [id] is, or the first of a group's.
  SlideShape? shape(String path, int id) {
    for (final s in slide(path).shapes) {
      if (!s.inherited && s.id == id) return s;
    }
    return null;
  }

  SlideTextLooks? looks(String path, int id, {(int, int)? cell}) => _reader.textLooks(path, id, cell: cell);

  List<SlideLayoutInfo> get layouts => _layouts ??= _reader.layouts();

  SlideBlock layoutPreview(String path) => _layoutDrawn[path] ??= _reader.layoutAt(path);

  /// The slide width and height, in points.
  (double, double) get stage {
    final first = slide(slides.first);
    return (first.width, first.height);
  }

  /// The layout the slide at [path] is built on.
  String? layoutOf(String path) {
    for (final rel in _relsOf(path)) {
      if (rel.type == _relLayout) return rel.target;
    }
    return null;
  }

  /// The master the layout at [path] belongs to.
  String? masterOf(String layout) {
    for (final rel in _relsOf(layout)) {
      if (rel.kind == 'slideMaster') return rel.target;
    }
    return null;
  }

  /// The deck's masters, in order.
  List<String> get masters {
    final out = <String>[];
    for (final layout in layouts) {
      if (!out.contains(layout.master)) out.add(layout.master);
    }
    return out;
  }

  /// The theme part the master at [path] uses.
  String? themeOf(String master) {
    for (final rel in _relsOf(master)) {
      if (rel.kind == 'theme') return rel.target;
    }
    return null;
  }

  /// The theme part's text, for a caller that reads its colours or name.
  XmlDocument? themeDoc(String master) {
    final theme = themeOf(master);
    return theme == null ? null : _doc(theme);
  }

  /// The words of the shape [id] as they stand, or null when it has none.
  XmlElement? textBody(String slide, int id, {(int, int)? cell}) {
    final doc = _doc(slide);
    final el = doc == null ? null : _anywhere(doc, id);
    if (el == null) return null;
    final holder = cell == null ? el : _cell(el, cell);
    final body = holder == null ? null : _kid(holder, 'txBody');
    return body?.copy();
  }

  /// The shape [id] wherever it is on the slide, a group's included.
  static XmlElement? _anywhere(XmlDocument slide, int id) {
    for (final el in _tree(slide).descendantElements) {
      final local = el.name.local;
      if (local != 'sp' && local != 'graphicFrame' && local != 'pic' && local != 'cxnSp' && local != 'grpSp') continue;
      if (PptxParser.idOf(el) == id) return el;
    }
    return null;
  }

  static XmlElement? _table(XmlElement el) {
    for (final e in el.descendantElements) {
      if (e.name.local == 'tbl') return e;
    }
    return null;
  }

  /// The cell at [at] (row, column) of the table in [el].
  static XmlElement? _cell(XmlElement el, (int, int) at) {
    final table = _table(el);
    if (table == null) return null;
    final rows = table.childElements.where((e) => e.name.local == 'tr').toList();
    if (at.$1 < 0 || at.$1 >= rows.length) return null;
    final cells = rows[at.$1].childElements.where((e) => e.name.local == 'tc').toList();
    if (at.$2 < 0 || at.$2 >= cells.length) return null;
    return cells[at.$2];
  }

  /// The table [id]'s column widths and row heights, in points, or null
  /// for an object that is not a table.
  (List<double>, List<double>)? tableGrid(String slide, int id) {
    final doc = _doc(slide);
    final el = doc == null ? null : _object(doc, id);
    final table = el == null ? null : _table(el);
    if (table == null) return null;
    final grid = _kid(table, 'tblGrid');
    return (
      <double>[
        for (final col in grid?.childElements ?? const <XmlElement>[])
          if (col.name.local == 'gridCol') (double.tryParse(_at(col, 'w') ?? '') ?? 0) / kEmuPerPoint,
      ],
      <double>[
        for (final row in table.childElements)
          if (row.name.local == 'tr') (double.tryParse(_at(row, 'h') ?? '') ?? 0) / kEmuPerPoint,
      ],
    );
  }

  // Changing.

  void _change(String label, void Function() edit) {
    final before = _now;
    _now = before.copy();
    try {
      edit();
    } on Object {
      _now = before;
      rethrow;
    }
    if (_unchanged(before, _now)) {
      _now = before;
      return;
    }
    _undo.add((before, label));
    _redo.clear();
    _moved(before, _now);
  }

  /// True when [b] holds the very parts [a] does, however they were
  /// written again.
  bool _unchanged(_State a, _State b) {
    if (a.gone.length != b.gone.length || !a.gone.containsAll(b.gone)) return false;
    if (a.bytes.length != b.bytes.length) return false;
    for (final e in b.bytes.entries) {
      if (!identical(a.bytes[e.key], e.value)) return false;
    }
    for (final key in <String>{...a.texts.keys, ...b.texts.keys}) {
      final was = a.texts[key], now = b.texts[key];
      if (identical(was, now) || was == now) continue;
      final original = _zip.find(key);
      final read = original == null ? null : utf8.decode(original.content, allowMalformed: true);
      if ((was ?? read) != (now ?? read)) return false;
    }
    return true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    final (state, label) = _undo.removeLast();
    _redo.add((_now, label));
    final was = _now;
    _now = state;
    _moved(was, _now);
  }

  /// Forgets the steps Redo would take, for a step undone that should never
  /// come back, such as a text box made and left empty.
  void forgetRedo() => _redo.clear();

  void redo() {
    if (_redo.isEmpty) return;
    final (state, label) = _redo.removeLast();
    _undo.add((_now, label));
    final was = _now;
    _now = state;
    _moved(was, _now);
  }

  /// Forgets what was drawn from the parts that changed between [a] and [b].
  void _moved(_State a, _State b) {
    _version++;
    _parser = null;
    _slides = null;
    _layouts = null;
    final touched = <String>{
      for (final k in <String>{...a.texts.keys, ...b.texts.keys})
        if (!identical(a.texts[k], b.texts[k])) k,
      ...a.gone.difference(b.gone),
      ...b.gone.difference(a.gone),
    };
    final wide = touched.any(
      (k) =>
          k.startsWith('ppt/slideLayouts/') ||
          k.startsWith('ppt/slideMasters/') ||
          k.startsWith('ppt/theme/'),
    );
    if (wide) {
      _drawn.clear();
      _objects.clear();
      _layoutDrawn.clear();
      return;
    }
    for (final k in touched) {
      final slide = k.startsWith('ppt/slides/_rels/')
          ? 'ppt/slides/${k.substring('ppt/slides/_rels/'.length, k.length - 5)}'
          : k;
      _drawn.remove(slide);
      _objects.remove(slide);
    }
  }

  /// The file as it now stands, or the bytes that were read when nothing
  /// has changed.
  Uint8List write() {
    if (!changed) return original;
    final lost = _unreached();
    final replace = <String, List<int>>{
      for (final entry in _now.texts.entries)
        if (!_now.gone.contains(entry.key) && !lost.contains(entry.key)) entry.key: utf8.encode(entry.value),
      for (final entry in _now.bytes.entries)
        if (!_now.gone.contains(entry.key) && !lost.contains(entry.key)) entry.key: entry.value,
    };
    final types = lost.isEmpty ? null : _doc(_types);
    if (types != null) {
      final declared = types.rootElement.childElements
          .where((e) => e.name.local == 'Override' && lost.contains((_at(e, 'PartName') ?? '').replaceFirst('/', '')))
          .toList();
      for (final e in declared) {
        e.remove();
      }
      if (declared.isNotEmpty) replace[_types] = utf8.encode(types.toXmlString());
    }
    return patchZip(
      original,
      replace,
      remove: <String>{
        for (final name in <String>{..._now.gone, ...lost})
          if (_zip.find(name) != null) name,
      },
    );
  }

  Set<String>? _reachedAtFirst;

  /// The parts no relationship reaches any more: ones something pointed at
  /// in the file as it was read, and ones an edit made. A part nothing
  /// pointed at even then is another program's business and stays.
  Set<String> _unreached() {
    final first = _reachedAtFirst ??= _reach((name) {
      final file = _zip.find(name);
      return file == null ? null : utf8.decode(file.content, allowMalformed: true);
    });
    final now = _reach(_textOf);
    final names = <String>{
      for (final file in _zip.files)
        if (file.isFile) file.name,
      ..._now.texts.keys,
      ..._now.bytes.keys,
    }..removeAll(_now.gone);
    return <String>{
      for (final name in names)
        if (name != _types && !now.contains(name) && (first.contains(name) || _zip.find(name) == null)) name,
    };
  }

  /// Every part the package's relationships lead to, and the relationship
  /// parts on the way, with the parts' texts as [text] gives them.
  static Set<String> _reach(String? Function(String name) text) {
    final seen = <String>{};
    final queue = <String>[''];
    while (queue.isNotEmpty) {
      final part = queue.removeLast();
      final rels = part.isEmpty ? '_rels/.rels' : _relsPath(part);
      final xml = text(rels);
      if (xml == null) continue;
      seen.add(rels);
      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(xml);
      } on XmlException {
        continue;
      }
      for (final r in doc.rootElement.childElements) {
        final target = _at(r, 'Target');
        if (target == null || _at(r, 'TargetMode') == 'External') continue;
        final to = _resolve(part, target);
        String decoded;
        try {
          decoded = Uri.decodeFull(to);
        } on ArgumentError {
          decoded = to;
        }
        for (final name in <String>{to, decoded}) {
          if (seen.add(name)) queue.add(name);
        }
      }
    }
    return seen;
  }

  // XML helpers.

  static XmlElement? _kid(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String? _relId(XmlElement e) {
    for (final a in e.attributes) {
      if (a.name.local == 'id' && a.name.prefix != null) return a.value;
    }
    return null;
  }

  static String? _at(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// The prefix [doc] binds [uri] to, bound on its root as [wanted] when it
  /// has none.
  static String _prefix(XmlDocument doc, String uri, String wanted) {
    final root = doc.rootElement;
    for (final a in root.attributes) {
      if (a.value == uri && a.name.prefix == 'xmlns') return a.name.local;
    }
    root.attributes.add(XmlAttribute(XmlName.parts(wanted, prefix: 'xmlns'), uri));
    return wanted;
  }

  static XmlElement _tree(XmlDocument slide) {
    final common = _kid(slide.rootElement, 'cSld');
    final tree = common == null ? null : _kid(common, 'spTree');
    if (tree == null) throw const FormatException('a slide with no shape tree');
    return tree;
  }

  static XmlElement? _object(XmlDocument slide, int id) {
    for (final el in _tree(slide).childElements) {
      if (PptxParser.idOf(el) == id) return el;
    }
    return null;
  }

  static int _nextId(XmlDocument slide) {
    var top = 1;
    for (final el in slide.rootElement.descendantElements) {
      if (el.name.local != 'cNvPr') continue;
      final id = int.tryParse(_at(el, 'id') ?? '') ?? 0;
      if (id > top) top = id;
    }
    return top + 1;
  }

  /// A fresh element in the namespace [uri] of [doc].
  static XmlElement _el(
    XmlDocument doc,
    String uri,
    String wanted,
    String local, [
    Map<String, String> attributes = const <String, String>{},
    List<XmlNode> children = const <XmlNode>[],
  ]) {
    final prefix = _prefix(doc, uri, wanted);
    return XmlElement(
      XmlName.parts(local, prefix: prefix),
      <XmlAttribute>[
        for (final e in attributes.entries) XmlAttribute(XmlName.qualified(e.key), e.value),
      ],
      children,
    );
  }

  /// Parses [xml], written with the prefixes p, a and r, into an element
  /// that uses whatever prefixes [doc] binds those namespaces to.
  static XmlElement _fragment(XmlDocument doc, String xml) {
    final p = _prefix(doc, kNsP, 'p');
    final a = _prefix(doc, kNsA, 'a');
    final r = _prefix(doc, kNsR, 'r');
    final parsed = XmlDocument.parse(
      '<w xmlns:p="$kNsP" xmlns:a="$kNsA" xmlns:r="$kNsR">$xml</w>',
    ).rootElement.firstElementChild!;
    String? swap(String? prefix) => switch (prefix) {
      'p' => p,
      'a' => a,
      'r' => r,
      _ => prefix,
    };
    XmlElement build(XmlElement e) => XmlElement(
      XmlName.parts(e.name.local, prefix: swap(e.name.prefix)),
      <XmlAttribute>[
        for (final at in e.attributes)
          XmlAttribute(XmlName.parts(at.name.local, prefix: swap(at.name.prefix)), at.value),
      ],
      <XmlNode>[
        for (final child in e.children) child is XmlElement ? build(child) : child.copy(),
      ],
    );
    return build(parsed);
  }

  // Relationships and content types.

  static String _relsPath(String part) {
    final cut = part.lastIndexOf('/');
    return '${part.substring(0, cut + 1)}_rels/${part.substring(cut + 1)}.rels';
  }

  List<DeckRel> _relsOf(String part) {
    final doc = _doc(_relsPath(part));
    if (doc == null) return const <DeckRel>[];
    return <DeckRel>[
      for (final r in doc.rootElement.childElements)
        if (_at(r, 'Id') case final id?)
          if (_at(r, 'Target') case final target?)
            DeckRel(
              id,
              _at(r, 'Type') ?? '',
              _at(r, 'TargetMode') == 'External' ? target : _resolve(part, target),
              external: _at(r, 'TargetMode') == 'External',
            ),
    ];
  }

  static String _resolve(String from, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final out = <String>[...from.split('/')..removeLast()];
    for (final step in target.split('/')) {
      if (step == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (step != '.' && step.isNotEmpty) {
        out.add(step);
      }
    }
    return out.join('/');
  }

  /// [target] as a relative path from the folder [from] is in.
  static String _relative(String from, String target) {
    final a = from.split('/')..removeLast();
    final b = target.split('/');
    var common = 0;
    while (common < a.length && common < b.length - 1 && a[common] == b[common]) {
      common++;
    }
    return <String>[
      for (var i = common; i < a.length; i++) '..',
      ...b.sublist(common),
    ].join('/');
  }

  XmlDocument _relsDoc(String part) =>
      _doc(_relsPath(part)) ??
      XmlDocument.parse(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
      );

  /// Relates [from] to [target] and returns the relationship's id, reusing
  /// one that already points there.
  String _relate(String from, String type, String target, {bool external = false}) {
    for (final rel in _relsOf(from)) {
      if (rel.type == type && rel.target == target && rel.external == external) return rel.id;
    }
    final doc = _relsDoc(from);
    final taken = <String>{
      for (final e in doc.rootElement.childElements) _at(e, 'Id') ?? '',
    };
    var n = taken.length + 1;
    while (taken.contains('rId$n')) {
      n++;
    }
    doc.rootElement.children.add(
      XmlElement(XmlName.parts('Relationship'), <XmlAttribute>[
        XmlAttribute(XmlName.parts('Id'), 'rId$n'),
        XmlAttribute(XmlName.parts('Type'), type),
        XmlAttribute(XmlName.parts('Target'), external ? target : _relative(from, target)),
        if (external) XmlAttribute(XmlName.parts('TargetMode'), 'External'),
      ]),
    );
    _put(_relsPath(from), doc);
    return 'rId$n';
  }

  void _unrelate(String from, bool Function(DeckRel rel) which) {
    final doc = _doc(_relsPath(from));
    if (doc == null) return;
    final rels = <String, DeckRel>{for (final rel in _relsOf(from)) rel.id: rel};
    for (final e in doc.rootElement.childElements.toList()) {
      final rel = rels[_at(e, 'Id') ?? ''];
      if (rel != null && which(rel)) e.remove();
    }
    _put(_relsPath(from), doc);
  }

  String? _contentType(String part) {
    final doc = _doc(_types);
    if (doc == null) return null;
    for (final e in doc.rootElement.childElements) {
      if (e.name.local == 'Override' && _at(e, 'PartName') == '/$part') return _at(e, 'ContentType');
    }
    return null;
  }

  void _declare(String part, String type) {
    final doc = _doc(_types);
    if (doc == null) return;
    doc.rootElement.children.add(
      XmlElement(XmlName.parts('Override'), <XmlAttribute>[
        XmlAttribute(XmlName.parts('PartName'), '/$part'),
        XmlAttribute(XmlName.parts('ContentType'), type),
      ]),
    );
    _put(_types, doc);
  }

  void _declareExtension(String extension, String type) {
    final doc = _doc(_types);
    if (doc == null) return;
    final known = doc.rootElement.childElements.any(
      (e) => e.name.local == 'Default' && (_at(e, 'Extension') ?? '').toLowerCase() == extension,
    );
    if (known) return;
    doc.rootElement.children.insert(
      0,
      XmlElement(XmlName.parts('Default'), <XmlAttribute>[
        XmlAttribute(XmlName.parts('Extension'), extension),
        XmlAttribute(XmlName.parts('ContentType'), type),
      ]),
    );
    _put(_types, doc);
  }

  void _undeclare(Set<String> parts) {
    final doc = _doc(_types);
    if (doc == null) return;
    for (final e in doc.rootElement.childElements.toList()) {
      if (e.name.local == 'Override' && parts.contains((_at(e, 'PartName') ?? '').replaceFirst('/', ''))) {
        e.remove();
      }
    }
    _put(_types, doc);
  }

  /// A part name like [pattern] with its number the first one free, where
  /// the pattern holds '#' for the number.
  String _fresh(String pattern) {
    var n = 1;
    while (_exists(pattern.replaceFirst('#', '$n'))) {
      n++;
    }
    return pattern.replaceFirst('#', '$n');
  }

  /// A copy of the part at [path] under a new name, with copies of the
  /// parts only it points at, and its own relationships pointing the same
  /// way as the original's.
  String _clonePart(String path) {
    final dot = path.lastIndexOf('.');
    final stem = path.substring(0, dot).replaceFirst(RegExp(r'\d+$'), '');
    final name = _fresh('$stem#${path.substring(dot)}');
    final text = _textOf(path);
    if (text != null && (path.endsWith('.xml') || path.endsWith('.rels'))) {
      _now.texts[name] = text;
    } else {
      final bytes = _now.bytes[path] ?? _zip.find(path)?.content;
      if (bytes != null) _now.bytes[name] = Uint8List.fromList(bytes);
    }
    final type = _contentType(path);
    if (type != null) _declare(name, type);
    final rels = _relsOf(path);
    if (rels.isNotEmpty) {
      final doc = _relsDoc(name);
      for (final rel in rels) {
        final target = rel.external || !_privateTargets.contains(rel.kind) ? rel.target : _clonePart(rel.target);
        doc.rootElement.children.add(
          XmlElement(XmlName.parts('Relationship'), <XmlAttribute>[
            XmlAttribute(XmlName.parts('Id'), rel.id),
            XmlAttribute(XmlName.parts('Type'), rel.type),
            XmlAttribute(XmlName.parts('Target'), rel.external ? target : _relative(name, target)),
            if (rel.external) XmlAttribute(XmlName.parts('TargetMode'), 'External'),
          ]),
        );
      }
      _put(_relsPath(name), doc);
    }
    return name;
  }

  // Objects on a slide.

  /// The transform element of [el], made where it has none.
  static XmlElement _transform(XmlDocument doc, XmlElement el, SlideBox was) {
    if (el.name.local == 'graphicFrame') {
      var xfrm = _kid(el, 'xfrm');
      if (xfrm == null) {
        xfrm = _el(doc, kNsP, 'p', 'xfrm');
        final nv = _kid(el, 'nvGraphicFramePr');
        el.children.insert(nv == null ? 0 : el.children.indexOf(nv) + 1, xfrm);
      }
      return xfrm;
    }
    final group = el.name.local == 'grpSp';
    var properties = _kid(el, group ? 'grpSpPr' : 'spPr');
    if (properties == null) {
      properties = _el(doc, kNsP, 'p', group ? 'grpSpPr' : 'spPr');
      final nv = el.childElements.where((c) => c.name.local.startsWith('nv')).firstOrNull;
      final blip = _kid(el, 'blipFill');
      final after = blip ?? nv;
      el.children.insert(after == null ? 0 : el.children.indexOf(after) + 1, properties);
    }
    var xfrm = _kid(properties, 'xfrm');
    if (xfrm == null) {
      xfrm = _el(doc, kNsA, 'a', 'xfrm');
      properties.children.insert(0, xfrm);
      if (group) {
        xfrm.children.addAll(<XmlNode>[
          _el(doc, kNsA, 'a', 'off', {'x': '${_emu(was.left)}', 'y': '${_emu(was.top)}'}),
          _el(doc, kNsA, 'a', 'ext', {'cx': '${_emu(was.width)}', 'cy': '${_emu(was.height)}'}),
          _el(doc, kNsA, 'a', 'chOff', {'x': '${_emu(was.left)}', 'y': '${_emu(was.top)}'}),
          _el(doc, kNsA, 'a', 'chExt', {'cx': '${_emu(was.width)}', 'cy': '${_emu(was.height)}'}),
        ]);
      }
    }
    return xfrm;
  }

  static void _setAttr(XmlElement e, String local, String? value) {
    final held = e.attributes.where((a) => a.name.local == local && a.name.prefix == null).firstOrNull;
    if (held != null && value != null) {
      held.value = value;
      return;
    }
    e.attributes.removeWhere((a) => a.name.local == local && a.name.prefix == null);
    if (value != null) e.attributes.add(XmlAttribute(XmlName.parts(local), value));
  }

  static void _place(XmlDocument doc, XmlElement el, SlideBox was, SlideBox box, double? rotation, {bool? flipH, bool? flipV}) {
    final xfrm = _transform(doc, el, was);
    var off = _kid(xfrm, 'off');
    var ext = _kid(xfrm, 'ext');
    if (off == null) {
      off = _el(doc, kNsA, 'a', 'off');
      xfrm.children.insert(0, off);
    }
    if (ext == null) {
      ext = _el(doc, kNsA, 'a', 'ext');
      xfrm.children.insert(xfrm.children.indexOf(off) + 1, ext);
    }
    _setAttr(off, 'x', '${_emu(box.left)}');
    _setAttr(off, 'y', '${_emu(box.top)}');
    _setAttr(ext, 'cx', '${_emu(box.width < 0 ? 0 : box.width)}');
    _setAttr(ext, 'cy', '${_emu(box.height < 0 ? 0 : box.height)}');
    if (rotation != null && el.name.local != 'graphicFrame') {
      final turn = ((rotation % 360) + 360) % 360;
      _setAttr(xfrm, 'rot', turn.abs() < 0.01 ? null : '${(turn * 60000).round()}');
    }
    if (flipH != null) _setAttr(xfrm, 'flipH', flipH ? '1' : null);
    if (flipV != null) _setAttr(xfrm, 'flipV', flipV ? '1' : null);
  }

  /// Moves, sizes or turns the object [id].
  void place(String slide, int id, SlideBox box, {double? rotation, bool? flipH, bool? flipV}) {
    final was = object(slide, id);
    if (was == null) return;
    _change(rotation != null && box == was.box ? 'Rotate' : 'Move', () {
      final doc = _doc(slide)!;
      final el = _object(doc, id);
      if (el == null) return;
      _place(doc, el, was.box, box, rotation, flipH: flipH, flipV: flipV);
      _put(slide, doc);
    });
  }

  void delete(String slide, Set<int> ids) {
    if (ids.isEmpty) return;
    _change('Delete', () {
      final doc = _doc(slide)!;
      for (final id in ids) {
        _object(doc, id)?.remove();
      }
      _put(slide, doc);
    });
  }

  SlideClip copy(String slide, Set<int> ids) {
    final doc = _doc(slide)!;
    final rels = <String, DeckRel>{for (final rel in _relsOf(slide)) rel.id: rel};
    final elements = <XmlElement>[];
    final boxes = <SlideBox>[];
    final looks = <int, SlideTextLooks?>{};
    for (final el in _tree(doc).childElements) {
      final id = PptxParser.idOf(el);
      if (id == null || !ids.contains(id)) continue;
      final copy = el.copy();
      final found = object(slide, id);
      if (found != null) {
        boxes.add(found.box);
        // A placeholder takes its place and its look from the slide's
        // layout, which another slide may not share; the copy says both
        // itself.
        if (found.placeholder != null) {
          looks[id] = this.looks(slide, id);
          _unplace(doc, copy, found.box, looks[id]);
        }
      }
      elements.add(copy);
    }
    return SlideClip(slide, elements, rels, boxes);
  }

  /// Turns a placeholder into a plain shape that states its own box and the
  /// look of each of its levels.
  static void _unplace(XmlDocument doc, XmlElement el, SlideBox box, SlideTextLooks? looks) {
    for (final nv in el.childElements.where((c) => c.name.local.startsWith('nv'))) {
      final properties = _kid(nv, 'nvPr');
      _kid(properties ?? nv, 'ph')?.remove();
      final locks = _kid(nv, 'cNvSpPr');
      if (locks != null) _kid(locks, 'spLocks')?.remove();
    }
    _place(doc, el, box, box, null);
    final body = _kid(el, 'txBody');
    if (body == null || looks == null) return;
    var list = _kid(body, 'lstStyle');
    if (list == null) {
      list = _el(doc, kNsA, 'a', 'lstStyle');
      final bodyPr = _kid(body, 'bodyPr');
      body.children.insert(bodyPr == null ? 0 : body.children.indexOf(bodyPr) + 1, list);
    }
    final own = <String, XmlElement>{for (final c in list.childElements) c.name.local: c};
    for (var i = 0; i < looks.levels.length && i < 9; i++) {
      final name = 'lvl${i + 1}pPr';
      if (own.containsKey(name)) continue;
      list.children.add(levelProperties(doc, name, looks.levels[i]));
    }
  }

  /// An `a:lvlNpPr` stating [look] outright.
  static XmlElement levelProperties(XmlDocument doc, String name, SlideTextLook look) {
    final a = _prefix(doc, kNsA, 'a');
    final colour = look.colour;
    final algn = switch (look.align) {
      DocAlign.center => ' algn="ctr"',
      DocAlign.end => ' algn="r"',
      DocAlign.justify => ' algn="just"',
      DocAlign.start => '',
    };
    final margin = look.bulleted
        ? ' marL="${342900 + look.level * 457200}" indent="-342900"'
        : ' marL="${look.level * 457200}" indent="0"';
    final bullet = !look.bulleted
        ? '<$a:buNone/>'
        : look.ordered
        ? '<$a:buAutoNum type="arabicPeriod"/>'
        : '<$a:buChar char="${_escape(look.bullet ?? '•')}"/>';
    final fill = colour == null
        ? ''
        : '<$a:solidFill><$a:srgbClr val="${(colour & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}"/></$a:solidFill>';
    return _fragment(
      doc,
      '<a:$name$algn$margin>${bullet.replaceAll('<$a:', '<a:')}'
      '<a:defRPr sz="${(look.size * 100).round()}" b="${look.bold ? 1 : 0}" i="${look.italic ? 1 : 0}"'
      '${look.underline ? ' u="sng"' : ''}>${fill.replaceAll('<$a:', '<a:').replaceAll('</$a:', '</a:')}</a:defRPr></a:$name>',
    );
  }

  static String _escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

  /// Puts [clip] on the slide at [slide], on top of everything, and returns
  /// the new objects' ids. Pasted onto the slide it came from, it lands a
  /// little down and to the right so it can be seen.
  List<int> paste(String slide, SlideClip clip, {String label = 'Paste'}) {
    final made = <int>[];
    _change(label, () {
      final doc = _doc(slide)!;
      final tree = _tree(doc);
      var next = _nextId(doc);
      final shift = clip.from == slide ? 10.0 : 0.0;
      final r = _prefix(doc, kNsR, 'r');
      final renamed = <String, String>{};
      for (var i = 0; i < clip.elements.length; i++) {
        final el = clip.elements[i].copy();
        final ids = <int, int>{};
        for (final nv in el.descendantElements.where((e) => e.name.local == 'cNvPr')) {
          final was = int.tryParse(_at(nv, 'id') ?? '') ?? 0;
          ids[was] = next;
          _setAttr(nv, 'id', '${next++}');
        }
        for (final link in el.descendantElements.where(
          (e) => e.name.local == 'stCxn' || e.name.local == 'endCxn',
        )) {
          final to = ids[int.tryParse(_at(link, 'id') ?? '') ?? -1];
          if (to == null) {
            link.remove();
          } else {
            _setAttr(link, 'id', '$to');
          }
        }
        for (final e in <XmlElement>[el, ...el.descendantElements]) {
          for (final at in e.attributes.toList()) {
            if (at.name.prefix != 'r' && at.name.prefix != r) continue;
            final rel = clip.rels[at.value];
            if (rel == null) continue;
            final id = renamed[at.value] ??= _relate(
              slide,
              rel.type,
              rel.external || !_privateTargets.contains(rel.kind) ? rel.target : _clonePart(rel.target),
              external: rel.external,
            );
            e.attributes.remove(at);
            e.attributes.add(XmlAttribute(XmlName.parts(at.name.local, prefix: r), id));
          }
        }
        if (shift > 0 && i < clip.boxes.length) {
          final box = clip.boxes[i];
          _place(
            doc,
            el,
            box,
            SlideBox(box.left + shift, box.top + shift, box.width, box.height),
            null,
          );
        }
        tree.children.add(el);
        made.add(PptxParser.idOf(el) ?? 0);
      }
      _put(slide, doc);
    });
    return made;
  }

  List<int> duplicate(String slide, Set<int> ids) => paste(slide, copy(slide, ids), label: 'Duplicate');

  /// Moves [id] through the stack of things on its slide.
  void order(String slide, int id, SlideOrder to) {
    _change('Order', () {
      final doc = _doc(slide)!;
      final tree = _tree(doc);
      final el = _object(doc, id);
      if (el == null) return;
      final things = tree.childElements
          .where((e) => PptxParser.idOf(e) != null && !const <String>{'nvGrpSpPr', 'grpSpPr'}.contains(e.name.local))
          .toList();
      final at = things.indexOf(el);
      final target = switch (to) {
        SlideOrder.front => things.length - 1,
        SlideOrder.forward => (at + 1).clamp(0, things.length - 1),
        SlideOrder.backward => (at - 1).clamp(0, things.length - 1),
        SlideOrder.back => 0,
      };
      if (target == at) return;
      el.remove();
      final rest = things.where((e) => e != el).toList();
      if (target >= rest.length) {
        tree.children.add(el);
      } else {
        tree.children.insert(tree.children.indexOf(rest[target]), el);
      }
      _put(slide, doc);
    });
  }

  XmlElement _box(XmlDocument doc, SlideBox box, {String extra = ''}) => _fragment(
    doc,
    '<a:xfrm$extra><a:off x="${_emu(box.left)}" y="${_emu(box.top)}"/>'
    '<a:ext cx="${_emu(box.width)}" cy="${_emu(box.height)}"/></a:xfrm>',
  );

  int _add(String slide, String label, XmlElement Function(XmlDocument doc, int id) make) {
    var made = 0;
    _change(label, () {
      final doc = _doc(slide)!;
      made = _nextId(doc);
      _tree(doc).children.add(make(doc, made));
      _put(slide, doc);
    });
    return made;
  }

  /// A new, empty text box at [box]; returns its id.
  int addTextBox(String slide, SlideBox box) => _add(slide, 'Text box', (doc, id) {
    final el = _fragment(
      doc,
      '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="TextBox $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>'
      '<p:txBody><a:bodyPr wrap="square" rtlCol="0"><a:spAutoFit/></a:bodyPr><a:lstStyle/>'
      '<a:p><a:endParaRPr lang="en-US" dirty="0"/></a:p></p:txBody></p:sp>',
    );
    _kid(el, 'spPr')!.children.insert(0, _box(doc, box));
    return el;
  });

  /// A new shape drawn in PowerPoint's preset [geometry], filled with the
  /// theme's first accent; returns its id.
  int addShape(String slide, String geometry, SlideBox box) => _add(slide, 'Shape', (doc, id) {
    final el = _fragment(
      doc,
      '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Shape $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
      '<p:spPr><a:prstGeom prst="$geometry"><a:avLst/></a:prstGeom>'
      '<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>'
      '<a:ln w="12700"><a:solidFill><a:schemeClr val="accent1"><a:lumMod val="50000"/></a:schemeClr></a:solidFill></a:ln></p:spPr>'
      '<p:style><a:lnRef idx="2"><a:schemeClr val="accent1"><a:shade val="50000"/></a:schemeClr></a:lnRef>'
      '<a:fillRef idx="1"><a:schemeClr val="accent1"/></a:fillRef>'
      '<a:effectRef idx="0"><a:schemeClr val="accent1"/></a:effectRef>'
      '<a:fontRef idx="minor"><a:schemeClr val="lt1"/></a:fontRef></p:style>'
      '<p:txBody><a:bodyPr rtlCol="0" anchor="ctr"/><a:lstStyle/>'
      '<a:p><a:pPr algn="ctr"/><a:endParaRPr lang="en-US" dirty="0"/></a:p></p:txBody></p:sp>',
    );
    _kid(el, 'spPr')!.children.insert(0, _box(doc, box));
    return el;
  });

  /// A new straight line from [from] to [to], in points; returns its id.
  int addLine(String slide, (double, double) from, (double, double) to) => _add(slide, 'Line', (doc, id) {
    final left = from.$1 < to.$1 ? from.$1 : to.$1;
    final top = from.$2 < to.$2 ? from.$2 : to.$2;
    final box = SlideBox(left, top, (to.$1 - from.$1).abs(), (to.$2 - from.$2).abs());
    final flipH = to.$1 < from.$1;
    final flipV = to.$2 < from.$2;
    final el = _fragment(
      doc,
      '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="$id" name="Line $id"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>'
      '<p:spPr><a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
      '<a:ln w="19050"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill></a:ln></p:spPr></p:cxnSp>',
    );
    _kid(el, 'spPr')!.children.insert(
      0,
      _box(doc, box, extra: '${flipH ? ' flipH="1"' : ''}${flipV ? ' flipV="1"' : ''}'),
    );
    return el;
  });

  /// A picture, stored as [extension] ('png', 'jpeg' or 'gif'), placed at
  /// [box]; returns its id.
  int addPicture(String slide, Uint8List bytes, String extension, SlideBox box) {
    var made = 0;
    _change('Picture', () {
      final media = _fresh('ppt/media/image#.$extension');
      _now.bytes[media] = bytes;
      _declareExtension(extension, 'image/${extension == 'jpg' ? 'jpeg' : extension}');
      final rel = _relate(slide, _relImage, media);
      final doc = _doc(slide)!;
      made = _nextId(doc);
      final el = _fragment(
        doc,
        '<p:pic><p:nvPicPr><p:cNvPr id="$made" name="Picture $made"/>'
        '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
        '<p:blipFill><a:blip r:embed="$rel"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
        '<p:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>',
      );
      _kid(el, 'spPr')!.children.insert(0, _box(doc, box));
      _tree(doc).children.add(el);
      _put(slide, doc);
    });
    _zipMedia = null;
    return made;
  }

  // Formatting objects.

  static const List<String> _fillKinds = <String>['noFill', 'solidFill', 'gradFill', 'blipFill', 'pattFill', 'grpFill'];

  /// The spPr children the format orders fills, lines and effects among.
  static const List<String> _spPrOrder = <String>[
    'xfrm',
    'custGeom',
    'prstGeom',
    'noFill',
    'solidFill',
    'gradFill',
    'blipFill',
    'pattFill',
    'grpFill',
    'ln',
    'effectLst',
    'effectDag',
    'scene3d',
    'sp3d',
    'extLst',
  ];

  static void _insertOrdered(XmlElement parent, XmlElement child, List<String> order) {
    final rank = order.indexOf(child.name.local);
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

  static String hexOf(int argb) => (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  XmlElement _solid(XmlDocument doc, int argb) {
    final alpha = (argb >> 24) & 0xFF;
    return _fragment(
      doc,
      '<a:solidFill><a:srgbClr val="${hexOf(argb)}">'
      '${alpha < 255 ? '<a:alpha val="${(alpha / 255 * 100000).round()}"/>' : ''}'
      '</a:srgbClr></a:solidFill>',
    );
  }

  void _format(String slide, int id, String label, void Function(XmlDocument doc, XmlElement properties, XmlElement el) edit) {
    _change(label, () {
      final doc = _doc(slide)!;
      final el = _object(doc, id);
      if (el == null) return;
      final group = el.name.local == 'grpSp';
      var properties = _kid(el, group ? 'grpSpPr' : 'spPr');
      if (properties == null) {
        final was = object(slide, id)!.box;
        _transform(doc, el, was);
        properties = _kid(el, group ? 'grpSpPr' : 'spPr')!;
      }
      edit(doc, properties, el);
      _put(slide, doc);
    });
  }

  /// Fills [id] with [argb], or with nothing when it is null.
  void setFill(String slide, int id, int? argb) => _format(slide, id, 'Fill colour', (doc, properties, el) {
    for (final c in properties.childElements.toList()) {
      if (_fillKinds.contains(c.name.local)) c.remove();
    }
    _insertOrdered(properties, argb == null ? _el(doc, kNsA, 'a', 'noFill') : _solid(doc, argb), _spPrOrder);
  });

  XmlElement _line(XmlDocument doc, XmlElement properties) {
    var ln = _kid(properties, 'ln');
    if (ln == null) {
      ln = _el(doc, kNsA, 'a', 'ln');
      _insertOrdered(properties, ln, _spPrOrder);
    }
    return ln;
  }

  static const List<String> _lnOrder = <String>[
    'noFill',
    'solidFill',
    'gradFill',
    'pattFill',
    'prstDash',
    'custDash',
    'round',
    'bevel',
    'miter',
    'headEnd',
    'tailEnd',
    'extLst',
  ];

  /// Sets the colour of [id]'s outline, or takes the outline away when
  /// [argb] is null.
  void setLineColour(String slide, int id, int? argb) => _format(slide, id, 'Border colour', (doc, properties, el) {
    final ln = _line(doc, properties);
    for (final c in ln.childElements.toList()) {
      if (const <String>{'noFill', 'solidFill', 'gradFill', 'pattFill'}.contains(c.name.local)) c.remove();
    }
    _insertOrdered(ln, argb == null ? _el(doc, kNsA, 'a', 'noFill') : _solid(doc, argb), _lnOrder);
    if (argb != null && _at(ln, 'w') == null) _setAttr(ln, 'w', '12700');
  });

  /// Sets the weight of [id]'s outline, in points.
  void setLineWeight(String slide, int id, double points) => _format(slide, id, 'Border weight', (doc, properties, el) {
    final ln = _line(doc, properties);
    _setAttr(ln, 'w', '${_emu(points)}');
    if (_kid(ln, 'noFill') != null) {
      _kid(ln, 'noFill')!.remove();
      _insertOrdered(ln, _fragment(doc, '<a:solidFill><a:schemeClr val="tx1"/></a:solidFill>'), _lnOrder);
    }
  });

  /// Sets [id]'s outline to PowerPoint's preset dash [dash], or solid.
  void setLineDash(String slide, int id, String? dash) => _format(slide, id, 'Border dash', (doc, properties, el) {
    final ln = _line(doc, properties);
    for (final c in ln.childElements.toList()) {
      if (c.name.local == 'prstDash' || c.name.local == 'custDash') c.remove();
    }
    _insertOrdered(ln, _el(doc, kNsA, 'a', 'prstDash', {'val': dash ?? 'solid'}), _lnOrder);
  });

  /// Gives [id] a drop shadow, or takes its shadow away.
  void setShadowed(String slide, int id, bool on) => _format(slide, id, 'Drop shadow', (doc, properties, el) {
    var effects = _kid(properties, 'effectLst');
    if (effects == null) {
      effects = _el(doc, kNsA, 'a', 'effectLst');
      _insertOrdered(properties, effects, _spPrOrder);
    }
    for (final c in effects.childElements.toList()) {
      if (c.name.local == 'outerShdw') c.remove();
    }
    if (on) {
      final shadow = _fragment(
        doc,
        '<a:outerShdw blurRad="50800" dist="38100" dir="2700000" algn="tl" rotWithShape="0">'
        '<a:srgbClr val="000000"><a:alpha val="40000"/></a:srgbClr></a:outerShdw>',
      );
      // outerShdw comes after blur, fillOverlay and glow, and before the rest.
      final after = effects.childElements.where(
        (c) => const <String>{'blur', 'fillOverlay', 'glow', 'innerShdw'}.contains(c.name.local),
      );
      effects.children.insert(after.isEmpty ? 0 : effects.children.indexOf(after.last) + 1, shadow);
    }
  });

  /// Sets how opaque the picture [id] is, 0 to 1.
  void setOpacity(String slide, int id, double opacity) => _change('Transparency', () {
    final doc = _doc(slide)!;
    final el = _object(doc, id);
    final fill = el == null ? null : _kid(el, 'blipFill');
    final blip = fill == null ? null : _kid(fill, 'blip');
    if (blip == null) return;
    for (final c in blip.childElements.toList()) {
      if (c.name.local == 'alphaModFix') c.remove();
    }
    if (opacity < 0.999) {
      final amount = _el(doc, kNsA, 'a', 'alphaModFix', {'amt': '${(opacity.clamp(0, 1) * 100000).round()}'});
      final ext = _kid(blip, 'extLst');
      if (ext == null) {
        blip.children.add(amount);
      } else {
        blip.children.insert(blip.children.indexOf(ext), amount);
      }
    }
    _put(slide, doc);
  });

  /// Sets the picture [id]'s brightness and contrast, each from -1 to 1.
  void setPictureLight(String slide, int id, {required double brightness, required double contrast}) =>
      _change('Adjustments', () {
        final doc = _doc(slide)!;
        final el = _object(doc, id);
        final fill = el == null ? null : _kid(el, 'blipFill');
        final blip = fill == null ? null : _kid(fill, 'blip');
        if (blip == null) return;
        for (final c in blip.childElements.toList()) {
          if (c.name.local == 'lum') c.remove();
        }
        if (brightness.abs() > 0.001 || contrast.abs() > 0.001) {
          final lum = _el(doc, kNsA, 'a', 'lum', {
            if (brightness.abs() > 0.001) 'bright': '${(brightness.clamp(-1, 1) * 100000).round()}',
            if (contrast.abs() > 0.001) 'contrast': '${(contrast.clamp(-1, 1) * 100000).round()}',
          });
          final ext = _kid(blip, 'extLst');
          if (ext == null) {
            blip.children.add(lum);
          } else {
            blip.children.insert(blip.children.indexOf(ext), lum);
          }
        }
        _put(slide, doc);
      });

  /// Puts [body] in place of [id]'s words; [height], when given, is the
  /// height in points a box that grows with its words now needs.
  void setText(String slide, int id, XmlElement body, {double? height, String label = 'Typing', (int, int)? cell}) =>
      _change(label, () {
        final doc = _doc(slide)!;
        final el = _anywhere(doc, id);
        if (el == null) return;
        final holder = cell == null ? el : _cell(el, cell);
        if (holder == null) return;
        final old = _kid(holder, 'txBody');
        final fresh = body.copy();
        // A cell's words are a:txBody, a shape's p:txBody.
        final placed = cell == null ? fresh : _renamed(doc, fresh, kNsA, 'a');
        if (old != null) {
          old.replace(placed);
        } else if (cell != null) {
          holder.children.insert(0, placed);
        } else {
          final after = _kid(el, 'style') ?? _kid(el, 'spPr');
          el.children.insert(after == null ? el.children.length : el.children.indexOf(after) + 1, placed);
        }
        if (height != null && cell != null) {
          _growRow(doc, el, cell.$1, height);
        } else if (height != null) {
          final was = object(slide, id);
          if (was != null && (was.box.height - height).abs() > 0.5) {
            _place(doc, el, was.box, SlideBox(was.box.left, was.box.top, was.box.width, height), null);
          }
        }
        _put(slide, doc);
      });

  /// [el] under the name [local] in the namespace [uri] of [doc].
  static XmlElement _renamed(XmlDocument doc, XmlElement el, String uri, String wanted) => XmlElement(
    XmlName.parts(el.name.local, prefix: _prefix(doc, uri, wanted)),
    <XmlAttribute>[for (final a in el.attributes) a.copy()],
    <XmlNode>[for (final c in el.children) c.copy()],
  );

  /// Makes the row [row] of the table in [el] at least [height] points
  /// tall, and the table's frame as tall as its rows.
  static void _growRow(XmlDocument doc, XmlElement el, int row, double height) {
    final table = _table(el);
    if (table == null) return;
    final rows = table.childElements.where((e) => e.name.local == 'tr').toList();
    if (row >= rows.length) return;
    final now = (double.tryParse(_at(rows[row], 'h') ?? '') ?? 0) / kEmuPerPoint;
    if (height <= now + 0.5) return;
    _setAttr(rows[row], 'h', '${_emu(height)}');
    _fitFrame(el, table);
  }

  /// The table's frame made as tall as its rows and as wide as its columns.
  static void _fitFrame(XmlElement el, XmlElement table) {
    var total = 0.0;
    for (final r in table.childElements.where((e) => e.name.local == 'tr')) {
      total += double.tryParse(_at(r, 'h') ?? '') ?? 0;
    }
    var wide = 0.0;
    final grid = _kid(table, 'tblGrid');
    for (final c in grid?.childElements ?? const <XmlElement>[]) {
      if (c.name.local == 'gridCol') wide += double.tryParse(_at(c, 'w') ?? '') ?? 0;
    }
    final xfrm = _kid(el, 'xfrm');
    final ext = xfrm == null ? null : _kid(xfrm, 'ext');
    if (ext == null) return;
    _setAttr(ext, 'cy', '${total.round()}');
    if (wide > 0) _setAttr(ext, 'cx', '${wide.round()}');
  }

  /// A new table of [rows] and [cols] empty cells filling [box], its first
  /// row a heading in the theme's first accent; returns its id.
  int addTable(String slide, int rows, int cols, SlideBox box) => _add(slide, 'Table', (doc, id) {
    final colWidth = _emu(box.width / cols);
    final rowHeight = _emu(box.height / rows);
    String cell(bool head) =>
        '<a:tc><a:txBody><a:bodyPr/>'
        '${head ? '<a:lstStyle><a:lvl1pPr><a:defRPr b="1"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle>' : '<a:lstStyle/>'}'
        '<a:p><a:endParaRPr lang="en-US" dirty="0"/></a:p></a:txBody><a:tcPr>'
        '<a:lnL w="12700"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:lnL>'
        '<a:lnR w="12700"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:lnR>'
        '<a:lnT w="12700"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:lnT>'
        '<a:lnB w="12700"><a:solidFill><a:schemeClr val="lt1"/></a:solidFill></a:lnB>'
        '${head ? '<a:solidFill><a:schemeClr val="accent1"/></a:solidFill>' : '<a:solidFill><a:schemeClr val="accent1"><a:lumMod val="20000"/><a:lumOff val="80000"/></a:schemeClr></a:solidFill>'}'
        '</a:tcPr></a:tc>';
    final xml = StringBuffer(
      '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/>'
      '<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="${_emu(box.left)}" y="${_emu(box.top)}"/><a:ext cx="${colWidth * cols}" cy="${rowHeight * rows}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl>'
      '<a:tblPr firstRow="1" bandRow="1"/><a:tblGrid>',
    );
    for (var c = 0; c < cols; c++) {
      xml.write('<a:gridCol w="$colWidth"/>');
    }
    xml.write('</a:tblGrid>');
    for (var r = 0; r < rows; r++) {
      xml.write('<a:tr h="$rowHeight">');
      for (var c = 0; c < cols; c++) {
        xml.write(cell(r == 0));
      }
      xml.write('</a:tr>');
    }
    xml.write('</a:tbl></a:graphicData></a:graphic></p:graphicFrame>');
    return _fragment(doc, xml.toString());
  });

  /// Puts a row of empty cells in the table [id] at [at], made like the row
  /// beside it.
  void addTableRow(String slide, int id, int at) => _change('Add row', () {
    final doc = _doc(slide)!;
    final el = _object(doc, id);
    final table = el == null ? null : _table(el);
    if (el == null || table == null) return;
    final rows = table.childElements.where((e) => e.name.local == 'tr').toList();
    if (rows.isEmpty) return;
    final model = rows[math.max(0, math.min(at, rows.length) - 1)];
    final row = model.copy();
    for (final tc in row.childElements.where((e) => e.name.local == 'tc')) {
      _emptyCell(doc, tc);
    }
    if (at >= rows.length) {
      table.children.insert(table.children.indexOf(rows.last) + 1, row);
    } else {
      table.children.insert(table.children.indexOf(rows[at]), row);
    }
    _fitFrame(el, table);
    _put(slide, doc);
  });

  /// Puts a column of empty cells in the table [id] at [at], as wide as the
  /// column beside it.
  void addTableColumn(String slide, int id, int at) => _change('Add column', () {
    final doc = _doc(slide)!;
    final el = _object(doc, id);
    final table = el == null ? null : _table(el);
    final grid = table == null ? null : _kid(table, 'tblGrid');
    if (el == null || table == null || grid == null) return;
    final cols = grid.childElements.where((e) => e.name.local == 'gridCol').toList();
    if (cols.isEmpty) return;
    final beside = math.max(0, math.min(at, cols.length) - 1);
    final col = cols[beside].copy();
    if (at >= cols.length) {
      grid.children.insert(grid.children.indexOf(cols.last) + 1, col);
    } else {
      grid.children.insert(grid.children.indexOf(cols[at]), col);
    }
    for (final tr in table.childElements.where((e) => e.name.local == 'tr')) {
      final cells = tr.childElements.where((e) => e.name.local == 'tc').toList();
      if (cells.isEmpty) continue;
      final cell = cells[math.min(beside, cells.length - 1)].copy();
      _emptyCell(doc, cell);
      cell.attributes.removeWhere((a) => const <String>{'gridSpan', 'hMerge'}.contains(a.name.local));
      if (at >= cells.length) {
        tr.children.insert(tr.children.indexOf(cells.last) + 1, cell);
      } else {
        tr.children.insert(tr.children.indexOf(cells[at]), cell);
      }
    }
    _fitFrame(el, table);
    _put(slide, doc);
  });

  /// Takes the row [row] out of the table [id]; the last row stays.
  void deleteTableRow(String slide, int id, int row) {
    final grid = tableGrid(slide, id);
    if (grid == null || grid.$2.length <= 1) return;
    _change('Delete row', () {
      final doc = _doc(slide)!;
      final el = _object(doc, id)!;
      final table = _table(el)!;
      final rows = table.childElements.where((e) => e.name.local == 'tr').toList();
      if (row < 0 || row >= rows.length) return;
      rows[row].remove();
      _fitFrame(el, table);
      _put(slide, doc);
    });
  }

  /// Takes the column [col] out of the table [id]; the last column stays.
  void deleteTableColumn(String slide, int id, int col) {
    final grid = tableGrid(slide, id);
    if (grid == null || grid.$1.length <= 1) return;
    _change('Delete column', () {
      final doc = _doc(slide)!;
      final el = _object(doc, id)!;
      final table = _table(el)!;
      final cols = _kid(table, 'tblGrid')!.childElements.where((e) => e.name.local == 'gridCol').toList();
      if (col < 0 || col >= cols.length) return;
      cols[col].remove();
      for (final tr in table.childElements.where((e) => e.name.local == 'tr')) {
        final cells = tr.childElements.where((e) => e.name.local == 'tc').toList();
        if (col < cells.length) cells[col].remove();
      }
      _fitFrame(el, table);
      _put(slide, doc);
    });
  }

  /// [tc] with its words taken out and its look kept.
  static void _emptyCell(XmlDocument doc, XmlElement tc) {
    tc.attributes.removeWhere((a) => const <String>{'rowSpan', 'vMerge'}.contains(a.name.local));
    final body = _kid(tc, 'txBody');
    if (body == null) return;
    final paragraphs = body.childElements.where((e) => e.name.local == 'p').toList();
    final first = paragraphs.isEmpty ? null : paragraphs.first;
    for (final p in paragraphs) {
      p.remove();
    }
    final end = first == null ? null : _kid(first, 'endParaRPr') ?? first.childElements.where((e) => e.name.local == 'r').map((r) => _kid(r, 'rPr')).whereType<XmlElement>().firstOrNull;
    final p = _el(doc, kNsA, 'a', 'p');
    if (end != null) {
      p.children.add(XmlElement(XmlName.parts('endParaRPr', prefix: end.name.prefix), <XmlAttribute>[for (final a in end.attributes) a.copy()], <XmlNode>[for (final c in end.children) c.copy()]));
    }
    body.children.add(p);
  }

  /// The document the slide at [path] is, for building a text body in it.
  XmlDocument slideDoc(String path) => _doc(path)!;

  // Slides.

  XmlDocument get _deckDoc => _doc(_deck)!;

  XmlElement _slideList(XmlDocument doc) {
    var list = _kid(doc.rootElement, 'sldIdLst');
    if (list == null) {
      list = _el(doc, kNsP, 'p', 'sldIdLst');
      final masters = _kid(doc.rootElement, 'sldMasterIdLst');
      final notes = _kid(doc.rootElement, 'notesMasterIdLst');
      final handout = _kid(doc.rootElement, 'handoutMasterIdLst');
      final after = handout ?? notes ?? masters;
      doc.rootElement.children.insert(after == null ? 0 : doc.rootElement.children.indexOf(after) + 1, list);
    }
    return list;
  }

  /// The sldId entries in order, each with the slide part it names.
  List<(XmlElement, String)> _entries(XmlDocument doc) {
    final rels = <String, String>{for (final rel in _relsOf(_deck)) rel.id: rel.target};
    return <(XmlElement, String)>[
      for (final e in _slideList(doc).childElements)
        if (rels[_relId(e) ?? ''] case final part?) (e, part),
    ];
  }

  static String? _plainId(XmlElement e) {
    for (final a in e.attributes) {
      if (a.name.local == 'id' && a.name.prefix == null) return a.value;
    }
    return null;
  }

  /// PowerPoint's sections, each with the slide ids it lists, in order.
  static List<XmlElement> _sectionLists(XmlDocument doc) => <XmlElement>[
    for (final e in doc.rootElement.descendantElements)
      if (e.name.local == 'sldIdLst' && e.parentElement?.name.local == 'section') e,
  ];

  /// Lists every slide in the section it belongs to, in the deck's order:
  /// a slide [placed] goes in the section of the slide before it, or the
  /// first section when it leads the deck, and a slide gone from the deck
  /// goes from its section.
  static void _resection(XmlDocument doc, List<String> order, Set<String> placed) {
    final lists = _sectionLists(doc);
    if (lists.isEmpty) return;
    final home = <String, int>{};
    for (var i = 0; i < lists.length; i++) {
      for (final e in lists[i].childElements) {
        final id = _plainId(e);
        if (id != null) home[id] = i;
      }
    }
    var previous = 0;
    final members = List<List<String>>.generate(lists.length, (_) => <String>[]);
    for (final id in order) {
      var section = placed.contains(id) ? previous : home[id] ?? previous;
      if (section < previous) section = previous;
      members[section].add(id);
      previous = section;
    }
    for (var i = 0; i < lists.length; i++) {
      final list = lists[i];
      final prefix = list.name.prefix;
      list.children.removeWhere((n) => n is XmlElement && n.name.local == 'sldId');
      list.children.addAll(<XmlNode>[
        for (final id in members[i])
          XmlElement(XmlName.parts('sldId', prefix: prefix), <XmlAttribute>[XmlAttribute(XmlName.parts('id'), id)]),
      ]);
    }
  }

  List<String> _slideIds(XmlDocument doc) => <String>[
    for (final (e, _) in _entries(doc)) _plainId(e) ?? '',
  ];

  /// Registers [part] as a slide at [at] in the deck's order.
  void _enlist(String part, int at) {
    final doc = _deckDoc;
    final list = _slideList(doc);
    final rel = _relate(_deck, _relSlide, part);
    var top = 255;
    for (final e in list.childElements) {
      final id = int.tryParse(_at(e, 'id') ?? '') ?? 0;
      if (id > top) top = id;
    }
    final entry = _el(doc, kNsP, 'p', 'sldId', {'id': '${top + 1}'});
    entry.attributes.add(XmlAttribute(XmlName.parts('id', prefix: _prefix(doc, kNsR, 'r')), rel));
    final entries = _entries(doc);
    if (at >= entries.length) {
      list.children.add(entry);
    } else {
      list.children.insert(list.children.indexOf(entries[at].$1), entry);
    }
    _resection(doc, _slideIds(doc), <String>{'${top + 1}'});
    _put(_deck, doc);
    if (_contentType(part) == null) _declare(part, _typeSlide);
  }

  static const Set<String> _noText = <String>{'pic', 'chart', 'tbl', 'dgm', 'media', 'clipArt', 'sldImg'};

  /// A new slide built on the layout at [layout], at [at] in the deck's
  /// order; returns its part.
  String addSlide(String layout, int at) {
    late String part;
    _change('New slide', () {
      part = _fresh('ppt/slides/slide#.xml');
      final shapes = StringBuffer();
      final source = _doc(layout);
      var id = 2;
      final common = source == null ? null : _kid(source.rootElement, 'cSld');
      final tree = common == null ? null : _kid(common, 'spTree');
      for (final el in tree?.childElements ?? const <XmlElement>[]) {
        final nv = el.childElements.where((c) => c.name.local.startsWith('nv')).firstOrNull;
        final nvPr = nv == null ? null : _kid(nv, 'nvPr');
        final ph = nvPr == null ? null : _kid(nvPr, 'ph');
        if (ph == null) continue;
        final type = _at(ph, 'type') ?? 'obj';
        if (const <String>{'dt', 'ftr', 'sldNum', 'hdr'}.contains(type)) continue;
        final named = nv == null ? null : _kid(nv, 'cNvPr');
        final name = _escape(named == null ? 'Placeholder $id' : _at(named, 'name') ?? 'Placeholder $id');
        final attributes = <String>[
          for (final a in ph.attributes) '${a.name.local}="${_escape(a.value)}"',
        ].join(' ');
        shapes.write(
          '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="$name"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
          '<p:nvPr><p:ph $attributes/></p:nvPr></p:nvSpPr><p:spPr/>'
          '${_noText.contains(type) ? '' : '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US" dirty="0"/></a:p></p:txBody>'}'
          '</p:sp>',
        );
        id++;
      }
      _now.texts[part] =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<p:sld xmlns:a="$kNsA" xmlns:r="$kNsR" xmlns:p="$kNsP"><p:cSld><p:spTree>'
          '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
          '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
          '$shapes</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>';
      _relate(part, _relLayout, layout);
      _enlist(part, at);
    });
    return part;
  }

  KeptSlide _keep(String slide) {
    final rels = _relsOf(slide);
    String? notes;
    var notesRels = const <DeckRel>[];
    for (final rel in rels) {
      if (rel.type == _relNotes) {
        notes = _textOf(rel.target);
        notesRels = _relsOf(rel.target);
      }
    }
    return KeptSlide(_textOf(slide)!, rels, notes, notesRels);
  }

  /// Makes a slide from [kept] at [at]; returns its part.
  String _remake(KeptSlide kept, int at) {
    final part = _fresh('ppt/slides/slide#.xml');
    _now.texts[part] = kept.xml;
    final doc = _relsDoc(part);
    for (final rel in kept.rels) {
      String target;
      if (rel.external) {
        target = rel.target;
      } else if (rel.type == _relNotes) {
        final notesXml = kept.notes;
        if (notesXml == null) continue;
        target = _fresh('ppt/notesSlides/notesSlide#.xml');
        _now.texts[target] = notesXml;
        _declare(target, _typeNotes);
        final notesDoc = _relsDoc(target);
        for (final back in kept.notesRels) {
          final to = back.type == _relSlide ? part : back.target;
          notesDoc.rootElement.children.add(
            XmlElement(XmlName.parts('Relationship'), <XmlAttribute>[
              XmlAttribute(XmlName.parts('Id'), back.id),
              XmlAttribute(XmlName.parts('Type'), back.type),
              XmlAttribute(XmlName.parts('Target'), back.external ? to : _relative(target, to)),
              if (back.external) XmlAttribute(XmlName.parts('TargetMode'), 'External'),
            ]),
          );
        }
        _put(_relsPath(target), notesDoc);
      } else if (_privateTargets.contains(rel.kind)) {
        target = _clonePart(rel.target);
      } else {
        target = rel.target;
      }
      doc.rootElement.children.add(
        XmlElement(XmlName.parts('Relationship'), <XmlAttribute>[
          XmlAttribute(XmlName.parts('Id'), rel.id),
          XmlAttribute(XmlName.parts('Type'), rel.type),
          XmlAttribute(XmlName.parts('Target'), rel.external ? target : _relative(part, target)),
          if (rel.external) XmlAttribute(XmlName.parts('TargetMode'), 'External'),
        ]),
      );
    }
    _put(_relsPath(part), doc);
    _enlist(part, at);
    return part;
  }

  /// Copies of [paths], each put straight after the last of them; returns
  /// the new parts.
  List<String> duplicateSlides(List<String> paths) {
    final made = <String>[];
    _change(paths.length == 1 ? 'Duplicate slide' : 'Duplicate slides', () {
      final order = slides;
      var at = paths.map(order.indexOf).reduce((a, b) => a > b ? a : b) + 1;
      for (final path in order.where(paths.contains)) {
        made.add(_remake(_keep(path), at++));
        _slides = null;
      }
    });
    return made;
  }

  SlidesClip copySlides(List<String> paths) =>
      SlidesClip(<KeptSlide>[for (final path in slides.where(paths.contains)) _keep(path)]);

  List<String> pasteSlides(SlidesClip clip, int at) {
    final made = <String>[];
    _change(clip.length == 1 ? 'Paste slide' : 'Paste slides', () {
      var place = at;
      for (final kept in clip.slides) {
        made.add(_remake(kept, place++));
      }
    });
    return made;
  }

  /// Takes [paths] out of the deck. The last slide cannot go.
  void deleteSlides(Set<String> paths, {String? label}) {
    if (paths.isEmpty || paths.length >= slides.length) return;
    _change(label ?? (paths.length == 1 ? 'Delete slide' : 'Delete slides'), () {
      final doc = _deckDoc;
      final gone = <String>{};
      final ids = <String>{};
      for (final (entry, part) in _entries(doc)) {
        if (!paths.contains(part)) continue;
        ids.add(_relId(entry) ?? '');
        entry.remove();
        gone
          ..add(part)
          ..add(_relsPath(part));
        for (final rel in _relsOf(part)) {
          if (rel.type == _relNotes) {
            gone
              ..add(rel.target)
              ..add(_relsPath(rel.target));
          }
        }
      }
      _resection(doc, _slideIds(doc), const <String>{});
      // Custom shows name slides too.
      for (final e in doc.rootElement.descendantElements.toList()) {
        if (e.name.local != 'sld' || e.parentElement?.name.local != 'sldLst') continue;
        if (e.attributes.any((a) => a.name.local == 'id' && ids.contains(a.value))) e.remove();
      }
      _put(_deck, doc);
      _unrelate(_deck, (rel) => ids.contains(rel.id));
      // Links from other slides to one that is gone go with it.
      for (final other in slides.where((s) => !paths.contains(s))) {
        final dead = <String>{
          for (final rel in _relsOf(other))
            if (paths.contains(rel.target)) rel.id,
        };
        if (dead.isEmpty) continue;
        final slideDoc = _doc(other)!;
        for (final e in slideDoc.rootElement.descendantElements.toList()) {
          if (e.attributes.any((a) => a.name.local == 'id' && dead.contains(a.value)) &&
              (e.name.local == 'hlinkClick' || e.name.local == 'hlinkHover')) {
            e.remove();
          }
        }
        _put(other, slideDoc);
        _unrelate(other, (rel) => dead.contains(rel.id));
      }
      _now.gone.addAll(gone);
      for (final name in gone) {
        _now.texts.remove(name);
      }
      _undeclare(gone);
    });
  }

  /// Moves [paths] together so the first of them lands at [to], counted in
  /// the deck without them.
  void moveSlides(List<String> paths, int to) {
    _change(paths.length == 1 ? 'Move slide' : 'Move slides', () {
      final doc = _deckDoc;
      final list = _slideList(doc);
      final entries = _entries(doc);
      final moving = <XmlElement>[
        for (final (e, part) in entries)
          if (paths.contains(part)) e,
      ];
      final rest = <XmlElement>[
        for (final (e, part) in entries)
          if (!paths.contains(part)) e,
      ];
      for (final e in moving) {
        e.remove();
      }
      final at = to.clamp(0, rest.length);
      final anchor = at < rest.length ? list.children.indexOf(rest[at]) : list.children.length;
      list.children.insertAll(anchor, moving);
      _resection(doc, _slideIds(doc), <String>{for (final e in moving) _plainId(e) ?? ''});
      _put(_deck, doc);
    });
  }

  /// Builds the slide at [slide] on the layout at [layout] instead.
  void setLayout(String slide, String layout) {
    if (layoutOf(slide) == layout) return;
    _change('Layout', () => _relayout(slide, layout));
  }

  void _relayout(String slide, String layout) {
    final doc = _doc(_relsPath(slide));
    if (doc == null) return;
    for (final e in doc.rootElement.childElements) {
      if (_at(e, 'Type') == _relLayout) _setAttr(e, 'Target', _relative(slide, layout));
    }
    _put(_relsPath(slide), doc);
  }

  /// Sets the ground of the slide at [slide] to [argb], or back to its
  /// layout's when null.
  void setBackground(String slide, int? argb) => _change('Background', () {
    final doc = _doc(slide)!;
    final common = _kid(doc.rootElement, 'cSld')!;
    _kid(common, 'bg')?.remove();
    if (argb != null) {
      final bg = _fragment(doc, '<p:bg><p:bgPr><a:noFill/><a:effectLst/></p:bgPr></p:bg>');
      final properties = _kid(bg, 'bgPr')!;
      _kid(properties, 'noFill')!.replace(_solid(doc, argb));
      common.children.insert(0, bg);
    }
    _put(slide, doc);
  });

  // Themes.

  /// Moves every slide onto the master at [master], each to the layout
  /// there made for the same thing.
  void useMaster(String master) {
    final targets = layouts.where((l) => l.master == master).toList();
    if (targets.isEmpty) return;
    _change('Theme', () {
      for (final slide in slides) {
        final now = layoutOf(slide);
        if (now == null) continue;
        final info = layouts.where((l) => l.path == now).firstOrNull;
        if (info == null || info.master == master) continue;
        final match = targets.where((l) => l.type != null && l.type == info.type).firstOrNull ??
            targets.where((l) => l.name == info.name).firstOrNull ??
            targets.where((l) => l.type == 'obj').firstOrNull ??
            targets.first;
        _relayout(slide, match.path);
      }
    });
  }

  /// Gives every master's theme [colours] (dk1, lt1, dk2, lt2, accent1 to
  /// 6, hlink, folHlink as 0xRRGGBB), the heading and body faces, and,
  /// for a [dark] theme, a colour map that sets dark grounds under light
  /// words.
  void applyTheme({
    required String name,
    required Map<String, int> colours,
    required String headings,
    required String body,
    required bool dark,
  }) {
    _change('Theme', () {
      final done = <String>{};
      for (final master in masters) {
        final theme = themeOf(master);
        if (theme != null && done.add(theme)) {
          final doc = _doc(theme);
          if (doc != null) {
            _retheme(doc, name, colours, headings, body);
            _put(theme, doc);
          }
        }
        final masterDoc = _doc(master);
        if (masterDoc == null) continue;
        final map = _kid(masterDoc.rootElement, 'clrMap');
        if (map != null) {
          _setAttr(map, 'bg1', dark ? 'dk1' : 'lt1');
          _setAttr(map, 'tx1', dark ? 'lt1' : 'dk1');
          _setAttr(map, 'bg2', dark ? 'dk2' : 'lt2');
          _setAttr(map, 'tx2', dark ? 'lt2' : 'dk2');
        }
        final common = _kid(masterDoc.rootElement, 'cSld');
        if (common != null) {
          _kid(common, 'bg')?.remove();
          common.children.insert(
            0,
            _fragment(
              masterDoc,
              '<p:bg><p:bgPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>',
            ),
          );
        }
        _put(master, masterDoc);
      }
    });
  }

  static void _retheme(XmlDocument doc, String name, Map<String, int> colours, String headings, String body) {
    _setAttr(doc.rootElement, 'name', name);
    XmlElement? find(String local) {
      for (final e in doc.rootElement.descendantElements) {
        if (e.name.local == local) return e;
      }
      return null;
    }

    final scheme = find('clrScheme');
    if (scheme != null) {
      _setAttr(scheme, 'name', name);
      for (final slot in scheme.childElements) {
        final value = colours[slot.name.local];
        if (value == null) continue;
        final prefix = slot.name.prefix;
        slot.children
          ..clear()
          ..add(
            XmlElement(XmlName.parts('srgbClr', prefix: prefix), <XmlAttribute>[
              XmlAttribute(XmlName.parts('val'), hexOf(value)),
            ]),
          );
      }
    }
    final fonts = find('fontScheme');
    if (fonts != null) {
      _setAttr(fonts, 'name', name);
      for (final (which, face) in <(String, String)>[('majorFont', headings), ('minorFont', body)]) {
        final group = _kid(fonts, which);
        final latin = group == null ? null : _kid(group, 'latin');
        if (latin != null) {
          _setAttr(latin, 'typeface', face);
          latin.attributes.removeWhere((a) => a.name.local == 'panose');
        }
      }
    }
  }

  /// The theme colours the master at [master] states, by slot name.
  Map<String, int> themeColours(String master) {
    final doc = themeDoc(master);
    final out = <String, int>{};
    if (doc == null) return out;
    for (final e in doc.rootElement.descendantElements) {
      if (e.name.local != 'clrScheme') continue;
      for (final slot in e.childElements) {
        for (final c in slot.childElements) {
          final value = c.name.local == 'srgbClr' ? _at(c, 'val') : c.name.local == 'sysClr' ? _at(c, 'lastClr') : null;
          final parsed = value == null ? null : int.tryParse(value, radix: 16);
          if (parsed != null) out[slot.name.local] = parsed;
        }
      }
      break;
    }
    return out;
  }

  /// The name the theme of [master] gives itself.
  String themeName(String master) {
    final doc = themeDoc(master);
    return doc == null ? 'Theme' : _at(doc.rootElement, 'name') ?? 'Theme';
  }
}
