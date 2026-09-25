import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'zip_patch.dart';

/// An Office package opened for patching: its parts read on demand, and the
/// ones changed written back through [patchZip], which copies every other
/// part across untouched.
class OoxmlPackage {
  OoxmlPackage(this.original) : _zip = ZipDecoder().decodeBytes(original);

  final Uint8List original;
  final Archive _zip;
  final Map<String, XmlDocument> _open = <String, XmlDocument>{};
  final Set<String> _changed = <String>{};

  /// The part at [name], parsed, or null when the package has none.
  XmlDocument? part(String name) {
    final held = _open[name];
    if (held != null) return held;
    final file = _zip.findFile(name);
    if (file == null) return null;
    final text = utf8.decode(file.content as List<int>, allowMalformed: true);
    return _open[name] = XmlDocument.parse(text);
  }

  /// Marks [name] as changed, so [write] puts it back.
  void touch(String name) => _changed.add(name);

  /// The bytes of the part at [name] as they are in the package, for one
  /// that is not XML, such as a picture.
  Uint8List? bytesOf(String name) {
    final file = _zip.findFile(name);
    if (file == null) return null;
    return Uint8List.fromList(file.content as List<int>);
  }

  /// True when the package holds a part at [name], or one has been made.
  bool has(String name) => _open.containsKey(name) || _zip.findFile(name) != null;

  final Map<String, List<int>> _madeBytes = <String, List<int>>{};

  /// Adds a new XML part at [name] and declares its [contentType].
  void create(String name, XmlDocument doc, {required String contentType}) {
    _open[name] = doc;
    touch(name);
    _declare(name, contentType);
  }

  /// Adds a new part at [name] holding [bytes], such as a picture, and
  /// declares its [contentType] unless its extension already has one.
  void createBytes(String name, List<int> bytes, {required String contentType}) {
    _madeBytes[name] = bytes;
    final types = part('[Content_Types].xml');
    if (types == null) return;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final known = types.rootElement.childElements.any(
      (e) => e.name.local == 'Default' && (e.getAttribute('Extension') ?? '').toLowerCase() == extension,
    );
    if (!known) _declare(name, contentType);
  }

  void _declare(String name, String contentType) {
    final types = part('[Content_Types].xml');
    if (types == null) return;
    final root = types.rootElement;
    root.children.add(XmlElement(XmlName.parts('Override'), [
      XmlAttribute(XmlName.parts('PartName'), '/$name'),
      XmlAttribute(XmlName.parts('ContentType'), contentType),
    ]));
    touch('[Content_Types].xml');
  }

  /// Adds a relationship of [type] from the part [from] to [target] and
  /// returns its new id. [target] is relative to [from]'s folder unless the
  /// relationship is [external].
  String relate(String from, String target, String type, {bool external = false}) {
    final slash = from.lastIndexOf('/');
    final rels = '${from.substring(0, slash + 1)}_rels/${from.substring(slash + 1)}.rels';
    var doc = part(rels);
    if (doc == null) {
      doc = XmlDocument.parse(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
      );
      _open[rels] = doc;
    }
    final taken = <String>{
      for (final e in doc.rootElement.childElements) e.getAttribute('Id') ?? '',
    };
    var n = taken.length + 1;
    while (taken.contains('rId$n')) {
      n++;
    }
    final id = 'rId$n';
    doc.rootElement.children.add(XmlElement(XmlName.parts('Relationship'), [
      XmlAttribute(XmlName.parts('Id'), id),
      XmlAttribute(XmlName.parts('Type'), type),
      XmlAttribute(XmlName.parts('Target'), target),
      if (external) XmlAttribute(XmlName.parts('TargetMode'), 'External'),
    ]));
    touch(rels);
    return id;
  }

  /// The package with every touched part written again, or the bytes that
  /// were read when nothing was touched.
  Uint8List write() {
    if (_changed.isEmpty && _madeBytes.isEmpty) return original;
    return patchZip(original, <String, List<int>>{
      for (final name in _changed)
        name: utf8.encode(_open[name]!.toXmlString()),
      ..._madeBytes,
    });
  }

  /// Where [target] points, relative to the part [from].
  static String resolve(String from, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final base = from.contains('/') ? from.substring(0, from.lastIndexOf('/')) : '';
    final parts = <String>[
      if (base.isNotEmpty) ...base.split('/'),
      ...target.split('/'),
    ];
    final out = <String>[];
    for (final p in parts) {
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (p != '.' && p.isNotEmpty) {
        out.add(p);
      }
    }
    return out.join('/');
  }

  /// The relationships of the part [name], by id.
  Map<String, String> relationships(String name) {
    final slash = name.lastIndexOf('/');
    final rels =
        '${name.substring(0, slash + 1)}_rels/${name.substring(slash + 1)}.rels';
    final doc = part(rels);
    if (doc == null) return const <String, String>{};
    return <String, String>{
      for (final rel in doc.rootElement.childElements)
        if (rel.getAttribute('Id') case final id?)
          if (rel.getAttribute('Target') case final target?)
            id: resolve(name, target),
    };
  }
}

/// How one markup language spells a run of text inside a paragraph.
class RunSpelling {
  const RunSpelling({
    required this.run,
    required this.text,
    required this.tab,
    required this.breaks,
    required this.properties,
    this.fields = const <String>{},
    this.after = const <String>{},
  });

  /// WordprocessingML: `w:r`, `w:t`, `w:tab`, `w:br` and `w:cr`, `w:rPr`.
  static const word = RunSpelling(
    run: 'r',
    text: 't',
    tab: 'tab',
    breaks: {'br', 'cr'},
    properties: 'rPr',
  );

  /// DrawingML: `a:r`, `a:t`, `a:br` between runs, `a:rPr`, and the
  /// paragraph's closing `a:endParaRPr`, which new runs go in front of.
  static const drawing = RunSpelling(
    run: 'r',
    text: 't',
    tab: '',
    breaks: {'br'},
    properties: 'rPr',
    fields: {'fld'},
    after: {'endParaRPr'},
  );

  final String run;
  final String text;
  final String tab;
  final Set<String> breaks;
  final String properties;

  /// Elements that carry text like a run but are not one, such as a slide
  /// number field: read, and left alone.
  final Set<String> fields;

  /// Elements that close a paragraph, which new runs are put before.
  final Set<String> after;
}

/// The text of paragraph [p], as the editor shows it: tabs as `\t` and line
/// breaks as `\n`.
String paragraphText(XmlElement p, RunSpelling spelling) {
  final out = StringBuffer();
  void walk(XmlElement e) {
    for (final child in e.childElements) {
      final local = child.name.local;
      if (local == spelling.run || spelling.fields.contains(local)) {
        for (final part in child.childElements) {
          final name = part.name.local;
          if (name == spelling.text) {
            out.write(part.innerText);
          } else if (name == spelling.tab && spelling.tab.isNotEmpty) {
            out.write('\t');
          } else if (spelling.breaks.contains(name)) {
            out.write('\n');
          }
        }
      } else if (spelling.breaks.contains(local)) {
        out.write('\n');
      } else if (local == 'hyperlink' || local == 'ins' || local == 'smartTag') {
        walk(child);
      }
    }
  }

  walk(p);
  return out.toString();
}

/// Sets paragraph [p]'s text to [text], keeping the look of its first run.
///
/// Every run that held only text goes, and the first one's properties carry
/// the new text. A run that holds anything else, a picture or a field, stays
/// where it is: quire does not know what it is, so it does not touch it.
void setParagraphText(XmlElement p, String text, RunSpelling spelling) {
  final prefix = p.name.prefix;
  XmlName named(String local) => XmlName.parts(local, prefix: prefix);

  final textual = <XmlElement>[];
  void collect(XmlElement e) {
    for (final child in e.childElements) {
      final local = child.name.local;
      if (local == spelling.run) {
        final kinds = child.childElements.map((c) => c.name.local).toSet()
          ..remove(spelling.properties);
        final onlyText = kinds.every(
          (k) =>
              k == spelling.text ||
              k == spelling.tab ||
              spelling.breaks.contains(k),
        );
        if (onlyText) textual.add(child);
      } else if (local == 'hyperlink' || local == 'ins' || local == 'smartTag') {
        collect(child);
      }
    }
  }

  collect(p);
  // DrawingML breaks sit between runs rather than inside them.
  if (spelling == RunSpelling.drawing) {
    for (final br in p.childElements
        .where((c) => spelling.breaks.contains(c.name.local))
        .toList()) {
      br.remove();
    }
  }

  XmlElement? properties;
  XmlElement? home;
  if (textual.isNotEmpty) {
    home = textual.first;
    properties = home.childElements
        .where((c) => c.name.local == spelling.properties)
        .firstOrNull
        ?.copy();
    for (final run in textual.skip(1)) {
      run.remove();
    }
  }

  // DrawingML has no break inside a run, so each line is a run of its own
  // with an a:br between; WordprocessingML breaks inside the one run.
  List<XmlElement> runsFor(String line) {
    XmlElement run(List<XmlNode> children) => XmlElement(named(spelling.run), [], [
          if (properties != null) properties.copy(),
          ...children,
        ]);
    XmlElement t(String s) => XmlElement(
          named(spelling.text),
          spelling == RunSpelling.word
              ? [XmlAttribute(XmlName.parts('space', prefix: 'xml'), 'preserve')]
              : [],
          [XmlText(s)],
        );
    if (spelling == RunSpelling.word) {
      final parts = <XmlNode>[];
      final lines = line.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) parts.add(XmlElement(named('br')));
        final tabs = lines[i].split('\t');
        for (var j = 0; j < tabs.length; j++) {
          if (j > 0) parts.add(XmlElement(named(spelling.tab)));
          if (tabs[j].isNotEmpty) parts.add(t(tabs[j]));
        }
      }
      return [run(parts)];
    }
    final out = <XmlElement>[];
    final lines = line.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        out.add(XmlElement(named('br'), [], [
          if (properties != null) properties.copy(),
        ]));
      }
      if (lines[i].isNotEmpty) out.add(run([t(lines[i])]));
    }
    return out;
  }

  final fresh = runsFor(text);
  if (home != null) {
    final parent = home.parentElement!;
    final at = parent.children.indexOf(home);
    home.remove();
    parent.children.insertAll(at, fresh);
    return;
  }
  // A paragraph with no text in it yet: after its properties, and before
  // whatever closes it.
  final closing = p.childElements
      .where((c) => spelling.after.contains(c.name.local))
      .firstOrNull;
  if (closing != null) {
    p.children.insertAll(p.children.indexOf(closing), fresh);
  } else {
    p.children.addAll(fresh);
  }
}

/// A Word document opened for its words to be changed.
class DocxPatch {
  DocxPatch(Uint8List bytes) : _package = OoxmlPackage(bytes) {
    final doc = _package.part(_part);
    if (doc == null) throw const FormatException('no word/document.xml');
    final body = doc.rootElement.childElements
        .where((e) => e.name.local == 'body')
        .firstOrNull;
    if (body == null) throw const FormatException('no document body');
    _paragraphs = body.descendantElements
        .where((e) => e.name.local == 'p' && e.name.prefix == doc.rootElement.name.prefix)
        .toList();
  }

  static const _part = 'word/document.xml';
  final OoxmlPackage _package;
  late final List<XmlElement> _paragraphs;

  /// Every paragraph's text, in reading order, table cells included.
  List<String> get paragraphs => <String>[
        for (final p in _paragraphs) paragraphText(p, RunSpelling.word),
      ];

  /// Sets paragraph [index] to [text]. Setting the text it already has is
  /// not a change.
  void setParagraph(int index, String text) {
    final p = _paragraphs[index];
    if (paragraphText(p, RunSpelling.word) == text) return;
    setParagraphText(p, text, RunSpelling.word);
    _package.touch(_part);
  }

  Uint8List write() => _package.write();
}

/// One paragraph of a deck: which slide and which text it is.
class SlideParagraph {
  const SlideParagraph(this.slide, this.text);
  final int slide;
  final String text;
}

/// A PowerPoint deck opened for the text in its shapes to be changed.
///
/// Only text already in a shape can be changed: adding a shape is a layout
/// decision about the slide, and quire does not make those.
class PptxPatch {
  PptxPatch(Uint8List bytes) : _package = OoxmlPackage(bytes) {
    const deck = 'ppt/presentation.xml';
    final presentation = _package.part(deck);
    if (presentation == null) throw const FormatException('no presentation');
    final rels = _package.relationships(deck);
    final ids = presentation.rootElement.descendantElements
        .where((e) => e.name.local == 'sldId');
    for (final id in ids) {
      final rid = id.attributes
          .where((a) => a.name.local == 'id' && a.name.prefix == 'r')
          .firstOrNull
          ?.value;
      final part = rels[rid];
      if (part == null) continue;
      final slide = _package.part(part);
      if (slide == null) continue;
      final index = _slides.length;
      _slides.add(part);
      for (final p in slide.rootElement.descendantElements
          .where((e) => e.name.local == 'p' && e.name.prefix == 'a')) {
        _paragraphs.add((index, part, p));
      }
    }
  }

  final OoxmlPackage _package;
  final List<String> _slides = <String>[];
  final List<(int, String, XmlElement)> _paragraphs = <(int, String, XmlElement)>[];

  int get slideCount => _slides.length;

  /// Every paragraph in every shape, slide by slide.
  List<SlideParagraph> get paragraphs => <SlideParagraph>[
        for (final (slide, _, p) in _paragraphs)
          SlideParagraph(slide, paragraphText(p, RunSpelling.drawing)),
      ];

  void setParagraph(int index, String text) {
    final (_, part, p) = _paragraphs[index];
    if (paragraphText(p, RunSpelling.drawing) == text) return;
    setParagraphText(p, text, RunSpelling.drawing);
    _package.touch(part);
  }

  Uint8List write() => _package.write();
}
