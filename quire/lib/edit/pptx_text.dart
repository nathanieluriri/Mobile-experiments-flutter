import 'package:xml/xml.dart';

import '../format/pptx_parser.dart';
import '../model/document.dart';
import 'pptx_deck.dart';

/// The character a line break inside a paragraph is held as. Flutter's text
/// layout breaks the line there, and the editor never mistakes it for the
/// end of a paragraph.
const String kSlideBreak = ' ';

/// The inline embed a run the editor does not model is kept as.
const String kSlideKept = 'slide-kept';

/// One paragraph as it was read: its element, the runs in it with their
/// looks, and the line the editor showed for it.
class _Read {
  _Read(this.element, this.look, this.line);
  final XmlElement element;
  final SlideTextLook look;
  final List<Map<String, dynamic>> line;

  /// For each character of the line's text, the run it came from.
  final List<int> sources = <int>[];

  /// The runs, by index: the element and its look.
  final List<(XmlElement, SlideTextLook)> runs = <(XmlElement, SlideTextLook)>[];
  String text = '';
}

/// A shape's words as the slide editor holds them: a flutter_quill Delta
/// with a line per paragraph.
///
/// Each line carries its level, its list and its alignment, and each run
/// carries only what sets it apart from its level's look, so a line moved
/// to another level takes that level's size, and a word made plain where
/// the level is bold says bold: false. Writing back keeps every paragraph
/// whose line did not change as it was, and in one that did, keeps each
/// run's own properties for the characters that stayed.
class SlideText {
  SlideText.read(this.body, this.looks) {
    final paragraphs = body == null
        ? const <XmlElement>[]
        : body!.childElements.where((e) => e.name.local == 'p').toList();
    for (var i = 0; i < paragraphs.length; i++) {
      final look = i < looks.paragraphs.length ? looks.paragraphs[i].$1 : looks.levels.first;
      final runLooks = i < looks.paragraphs.length ? looks.paragraphs[i].$2 : const <SlideTextLook>[];
      _paragraphs.add(_readParagraph(paragraphs[i], look, runLooks));
    }
    if (_paragraphs.isEmpty) {
      ops.add(<String, dynamic>{'insert': '\n'});
    }
    for (final p in _paragraphs) {
      ops.addAll(p.line);
    }
  }

  /// The shape's text body as it was, or null for a shape with none.
  final XmlElement? body;
  final SlideTextLooks looks;
  final List<_Read> _paragraphs = <_Read>[];

  /// The elements an embed stands for, by its key.
  final Map<String, XmlElement> kept = <String, XmlElement>{};

  /// What each kept element shows, by its key.
  final Map<String, String> keptText = <String, String>{};

  /// The Delta the editor opens with.
  final List<Map<String, dynamic>> ops = <Map<String, dynamic>>[];

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static String? _at(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  static XmlElement? _kid(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c;
    }
    return null;
  }

  static String? _script(XmlElement? rPr) {
    final shift = int.tryParse((rPr == null ? null : _at(rPr, 'baseline')) ?? '') ?? 0;
    return shift > 0 ? 'super' : shift < 0 ? 'sub' : null;
  }

  static bool _struck(XmlElement? rPr) {
    final v = rPr == null ? null : _at(rPr, 'strike');
    return v != null && v != 'noStrike';
  }

  /// What sets [run] apart from [base], in Delta attributes.
  static Map<String, dynamic> attributesOf(SlideTextLook run, SlideTextLook base, XmlElement? rPr) => <String, dynamic>{
    if (run.bold != base.bold) 'bold': run.bold,
    if (run.italic != base.italic) 'italic': run.italic,
    if (run.underline != base.underline) 'underline': run.underline,
    if (_struck(rPr)) 'strike': true,
    if ((run.size - base.size).abs() > 0.01) 'size': _size(run.size),
    if (run.colour != null && (run.colour! & 0xFFFFFF) != ((base.colour ?? 0xFF000000) & 0xFFFFFF)) 'color': _hex(run.colour!),
    if (_script(rPr) != null) 'script': _script(rPr),
  };

  static String _size(double points) =>
      points == points.roundToDouble() ? '${points.round()}' : points.toStringAsFixed(1);

  /// The line attributes a paragraph set as [look] carries.
  static Map<String, dynamic> lineOf(SlideTextLook look) => <String, dynamic>{
    if (look.level > 0) 'indent': look.level,
    if (look.bulleted) 'list': look.ordered ? 'ordered' : 'bullet',
    if (look.align != DocAlign.start)
      'align': switch (look.align) {
        DocAlign.center => 'center',
        DocAlign.end => 'right',
        _ => 'justify',
      },
  };

  _Read _readParagraph(XmlElement p, SlideTextLook look, List<SlideTextLook> runLooks) {
    final base = looks.levels[look.level.clamp(0, looks.levels.length - 1)];
    final line = <Map<String, dynamic>>[];
    final read = _Read(p, look, line);
    final text = StringBuffer();
    var runIndex = 0;
    void add(String insert, Map<String, dynamic> attributes, int source) {
      if (insert.isEmpty) return;
      line.add(<String, dynamic>{'insert': insert, if (attributes.isNotEmpty) 'attributes': attributes});
      for (var i = 0; i < insert.length; i++) {
        read.sources.add(source);
      }
      text.write(insert);
    }

    for (final child in p.childElements) {
      switch (child.name.local) {
        case 'pPr':
        case 'endParaRPr':
          break;
        case 'r':
          final rPr = _kid(child, 'rPr');
          final runLook = runIndex < runLooks.length ? runLooks[runIndex] : look;
          runIndex++;
          read.runs.add((child, runLook));
          final t = _kid(child, 't');
          add(t?.innerText ?? '', attributesOf(runLook, base, rPr), read.runs.length - 1);
        case 'br':
          final rPr = _kid(child, 'rPr');
          read.runs.add((child, look));
          add(kSlideBreak, attributesOf(look, base, rPr), read.runs.length - 1);
        default:
          // A field, a piece of maths, or anything else this editor does not
          // model: kept whole, shown as its text, and written back as it was.
          final key = 'k${kept.length}';
          kept[key] = child;
          if (child.name.local == 'fld') {
            final runLook = runIndex < runLooks.length ? runLooks[runIndex] : look;
            runIndex++;
            read.runs.add((child, runLook));
          } else {
            read.runs.add((child, look));
          }
          keptText[key] = child.descendantElements
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join();
          line.add(<String, dynamic>{
            'insert': <String, dynamic>{kSlideKept: key},
          });
          read.sources.add(read.runs.length - 1);
          text.write('￼');
      }
    }
    line.add(<String, dynamic>{
      'insert': '\n',
      if (lineOf(look).isNotEmpty) 'attributes': lineOf(look),
    });
    read.text = text.toString();
    return read;
  }

  // Writing.

  /// The text body the edited [ops] make, built in [doc]'s namespaces.
  XmlElement write(XmlDocument doc, List<dynamic> ops) {
    final lines = _lines(ops);
    final a = _prefixOf(doc, kNsA, 'a');
    final p = _prefixOf(doc, kNsP, 'p');
    final out = body?.copy() ??
        XmlElement(XmlName.parts('txBody', prefix: p), const <XmlAttribute>[], <XmlNode>[
          XmlElement(XmlName.parts('bodyPr', prefix: a)),
          XmlElement(XmlName.parts('lstStyle', prefix: a)),
        ]);
    for (final e in out.childElements.where((e) => e.name.local == 'p').toList()) {
      e.remove();
    }
    final pairs = _pair(lines);
    for (var i = 0; i < lines.length; i++) {
      final source = pairs[i];
      final read = source == null ? null : _paragraphs[source];
      if (read != null && _same(read.line, lines[i])) {
        out.children.add(read.element.copy());
        continue;
      }
      out.children.add(_paragraph(doc, a, lines[i], read, _neighbour(pairs, i)));
    }
    return out;
  }

  static String _prefixOf(XmlDocument doc, String uri, String wanted) {
    for (final at in doc.rootElement.attributes) {
      if (at.value == uri && at.name.prefix == 'xmlns') return at.name.local;
    }
    return wanted;
  }

  /// The ops cut into lines, each ending with its newline op.
  static List<List<Map<String, dynamic>>> _lines(List<dynamic> ops) {
    final out = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];
    for (final raw in ops) {
      final op = Map<String, dynamic>.from(raw as Map);
      final insert = op['insert'];
      if (insert is! String) {
        current.add(op);
        continue;
      }
      final pieces = insert.split('\n');
      for (var i = 0; i < pieces.length; i++) {
        if (pieces[i].isNotEmpty) {
          current.add(<String, dynamic>{'insert': pieces[i], if (op['attributes'] != null) 'attributes': op['attributes']});
        }
        if (i < pieces.length - 1) {
          current.add(<String, dynamic>{'insert': '\n', if (op['attributes'] != null) 'attributes': op['attributes']});
          out.add(current);
          current = <Map<String, dynamic>>[];
        }
      }
    }
    if (current.isNotEmpty) out.add(current..add(<String, dynamic>{'insert': '\n'}));
    // The editor's own last line is an empty one only when the text box was.
    return out;
  }

  static String _textOf(List<Map<String, dynamic>> line) => line
      .map((op) => op['insert'] is String ? (op['insert'] == '\n' ? '' : op['insert'] as String) : '￼')
      .join();

  /// A string that two Deltas share exactly when they hold the same words
  /// with the same looks, however their runs are cut.
  static String signatureOf(List<dynamic> ops) => _lines(ops).map(_signature).join('\n');

  static bool _same(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) =>
      _signature(a) == _signature(b);

  static String _signature(List<Map<String, dynamic>> line) {
    final merged = <String>[];
    String? lastAttrs;
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) merged.add('$lastAttrs|$text');
      text.clear();
    }

    for (final op in line) {
      final insert = op['insert'];
      final attrs = _canon(op['attributes']);
      if (insert is String && insert != '\n') {
        if (attrs != lastAttrs) flush();
        lastAttrs = attrs;
        text.write(insert);
      } else {
        flush();
        lastAttrs = null;
        merged.add(insert is String ? 'EOL$attrs' : 'E${insert.toString()}');
      }
    }
    flush();
    return merged.join('\u0001');
  }

  static String _canon(Object? attrs) {
    if (attrs is! Map) return '';
    final keys = attrs.keys.map((k) => '$k').toList()..sort();
    return keys.map((k) => '$k=${attrs[k]}').join(',');
  }

  /// For each new line, the paragraph it was read from, if any: lines that
  /// are unchanged anchor the pairing, and the lines between two anchors
  /// pair with the paragraphs between them most like them.
  List<int?> _pair(List<List<Map<String, dynamic>>> lines) {
    final olds = <String>[for (final p in _paragraphs) _signature(p.line)];
    final news = <String>[for (final l in lines) _signature(l)];
    final n = olds.length, m = news.length;
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = olds[i] == news[j]
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] > table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
      }
    }
    final out = List<int?>.filled(m, null);
    final anchors = <(int, int)>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (olds[i] == news[j]) {
        anchors.add((i, j));
        out[j] = i;
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    // Between anchors, each changed line takes the unused paragraph whose
    // text shares the most with it, in order.
    var lastOld = -1, lastNew = -1;
    for (final (ao, an) in <(int, int)>[...anchors, (n, m)]) {
      final freeOld = <int>[for (var k = lastOld + 1; k < ao; k++) k];
      var from = 0;
      for (var k = lastNew + 1; k < an; k++) {
        if (from >= freeOld.length) break;
        final text = _textOf(lines[k]);
        var best = from;
        var bestScore = -1;
        for (var c = from; c < freeOld.length; c++) {
          final score = _shared(_paragraphs[freeOld[c]].text, text);
          if (score > bestScore) {
            bestScore = score;
            best = c;
          }
        }
        // Lines left without a paragraph are new ones; a new line takes
        // after its neighbour.
        if (bestScore <= 0 && freeOld.length - from < an - k) continue;
        out[k] = freeOld[best];
        from = best + 1;
      }
      lastOld = ao;
      lastNew = an;
    }
    return out;
  }

  /// How many characters the longest common run of [a] and [b] shares,
  /// counted by common prefix and suffix, the cheap measure of kinship.
  static int _shared(String a, String b) {
    var p = 0;
    while (p < a.length && p < b.length && a.codeUnitAt(p) == b.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < a.length - p && s < b.length - p && a.codeUnitAt(a.length - 1 - s) == b.codeUnitAt(b.length - 1 - s)) {
      s++;
    }
    return p + s;
  }

  /// The paragraph a new line with no source of its own takes after: the
  /// one before it, or the one after it for a new first line.
  _Read? _neighbour(List<int?> pairs, int i) {
    for (var k = i - 1; k >= 0; k--) {
      if (pairs[k] != null) return _paragraphs[pairs[k]!];
    }
    for (var k = i + 1; k < pairs.length; k++) {
      if (pairs[k] != null) return _paragraphs[pairs[k]!];
    }
    return _paragraphs.isEmpty ? null : _paragraphs.first;
  }

  /// For each character of [now], the index in [was] it was kept from, or
  /// -1 for one that was typed.
  static List<int> _align(String was, String now) {
    final out = List<int>.filled(now.length, -1);
    final n = was.length, m = now.length;
    if (n * m > 4000000) {
      var p = 0;
      while (p < n && p < m && was.codeUnitAt(p) == now.codeUnitAt(p)) {
        out[p] = p;
        p++;
      }
      var s = 0;
      while (s < n - p && s < m - p && was.codeUnitAt(n - 1 - s) == now.codeUnitAt(m - 1 - s)) {
        out[m - 1 - s] = n - 1 - s;
        s++;
      }
      return out;
    }
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = was.codeUnitAt(i) == now.codeUnitAt(j)
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] > table[i][j + 1] ? table[i + 1][j] : table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (was.codeUnitAt(i) == now.codeUnitAt(j)) {
        out[j] = i;
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

  XmlElement _paragraph(
    XmlDocument doc,
    String a,
    List<Map<String, dynamic>> line,
    _Read? read,
    _Read? neighbour,
  ) {
    XmlElement el(String local, [Map<String, String> attributes = const <String, String>{}, List<XmlNode> children = const <XmlNode>[]]) =>
        XmlElement(XmlName.parts(local, prefix: a), <XmlAttribute>[
          for (final e in attributes.entries) XmlAttribute(XmlName.parts(e.key), e.value),
        ], children);

    final template = read ?? neighbour;
    final lineAttrs = line.last['attributes'] is Map ? Map<String, dynamic>.from(line.last['attributes'] as Map) : <String, dynamic>{};
    final level = (lineAttrs['indent'] as int?) ?? 0;
    final base = looks.levels[level.clamp(0, looks.levels.length - 1)];
    final was = template?.look ?? base;

    // The paragraph's own properties.
    final pPr = template == null ? null : _kid(template.element, 'pPr')?.copy();
    final props = pPr ?? el('pPr');
    if (level != was.level) {
      props.attributes.removeWhere((at) => at.name.local == 'marL' || at.name.local == 'indent');
    }
    _set(props, 'lvl', level == 0 ? null : '$level');
    final align = switch (lineAttrs['align']) {
      'center' => DocAlign.center,
      'right' => DocAlign.end,
      'justify' => DocAlign.justify,
      _ => DocAlign.start,
    };
    if (align != was.align || level != was.level) {
      _set(
        props,
        'algn',
        align == base.align
            ? null
            : switch (align) {
                DocAlign.center => 'ctr',
                DocAlign.end => 'r',
                DocAlign.justify => 'just',
                DocAlign.start => 'l',
              },
      );
    }
    final list = lineAttrs['list'] as String?;
    final wasList = was.bulleted ? (was.ordered ? 'ordered' : 'bullet') : null;
    final baseList = base.bulleted ? (base.ordered ? 'ordered' : 'bullet') : null;
    if (list != wasList || level != was.level) {
      for (final c in props.childElements.toList()) {
        if (c.name.local.startsWith('bu')) c.remove();
      }
      if (list != baseList) {
        final bullet = switch (list) {
          'bullet' => el('buChar', {'char': base.bullet ?? '•'}),
          'ordered' => el('buAutoNum', {'type': 'arabicPeriod'}),
          _ => el('buNone'),
        };
        // Bullets come after spacing and before tabs and defaults.
        final after = props.childElements.where(
          (c) => const <String>{'lnSpc', 'spcBef', 'spcAft'}.contains(c.name.local),
        );
        props.children.insert(after.isEmpty ? 0 : props.children.indexOf(after.last) + 1, bullet);
        if (list != null && !props.attributes.any((at) => at.name.local == 'indent')) {
          _set(props, 'marL', '${342900 + level * 457200}');
          _set(props, 'indent', '-342900');
        } else if (list == null && props.attributes.any((at) => at.name.local == 'indent' && at.value.startsWith('-'))) {
          _set(props, 'indent', '0');
          _set(props, 'marL', '${level * 457200}');
        }
      }
    }

    final out = el('p');
    if (props.attributes.isNotEmpty || props.children.isNotEmpty) out.children.add(props);

    // The runs.
    final text = _textOf(line);
    final kept = read == null ? List<int>.filled(text.length, -1) : _align(read.text, text);
    final chars = <(String, Map<String, dynamic>, Object?)>[];
    for (final op in line) {
      final insert = op['insert'];
      final attrs = op['attributes'] is Map ? Map<String, dynamic>.from(op['attributes'] as Map) : <String, dynamic>{};
      if (insert is String) {
        if (insert == '\n') continue;
        for (final ch in insert.runes) {
          final s = String.fromCharCode(ch);
          for (var u = 0; u < s.length; u++) {
            chars.add((u == 0 ? s : '', attrs, null));
          }
        }
      } else if (insert is Map) {
        chars.add(('￼', attrs, insert[kSlideKept]));
      }
    }
    // The run each character takes its properties from: the run it came
    // from, or for a typed one the run of the character before it.
    final runOf = List<int?>.filled(chars.length, null);
    int? previous;
    for (var i = 0; i < chars.length; i++) {
      final from = i < kept.length ? kept[i] : -1;
      if (from >= 0 && read != null && from < read.sources.length) {
        previous = read.sources[from];
      }
      runOf[i] = previous;
    }
    int? next;
    for (var i = chars.length - 1; i >= 0; i--) {
      if (runOf[i] != null) {
        next = runOf[i];
      } else {
        runOf[i] = next;
      }
    }

    final runs = template?.runs ?? const <(XmlElement, SlideTextLook)>[];
    final endProperties = template == null ? null : _kid(template.element, 'endParaRPr');
    XmlElement? templateRPr(int? run) {
      if (run != null && run < runs.length) {
        final (element, _) = runs[run];
        final own = _kid(element, 'rPr');
        if (own != null) return own;
        return null;
      }
      final first = runs.where((r) => r.$1.name.local == 'r').firstOrNull;
      return (first == null ? null : _kid(first.$1, 'rPr')) ?? endProperties;
    }

    SlideTextLook lookOf(int? run) {
      if (run != null && run < runs.length) return runs[run].$2;
      return runs.isEmpty ? was : runs.first.$2;
    }

    var i = 0;
    while (i < chars.length) {
      final (ch, attrs, key) = chars[i];
      if (key != null) {
        final element = this.kept[key];
        if (element != null) out.children.add(element.copy());
        i++;
        continue;
      }
      if (ch == kSlideBreak) {
        final rPr = _runProperties(doc, a, templateRPr(runOf[i]), lookOf(runOf[i]), base, attrs);
        out.children.add(el('br', const <String, String>{}, <XmlNode>[rPr]));
        i++;
        continue;
      }
      final buffer = StringBuffer(ch);
      var j = i + 1;
      while (j < chars.length &&
          chars[j].$3 == null &&
          chars[j].$1 != kSlideBreak &&
          runOf[j] == runOf[i] &&
          _canon(chars[j].$2) == _canon(attrs)) {
        buffer.write(chars[j].$1);
        j++;
      }
      final rPr = _runProperties(doc, a, templateRPr(runOf[i]), lookOf(runOf[i]), base, attrs);
      out.children.add(
        el('r', const <String, String>{}, <XmlNode>[
          rPr,
          el('t', const <String, String>{}, <XmlNode>[XmlText(buffer.toString())]),
        ]),
      );
      i = j;
    }
    final end = endProperties?.copy() ?? templateRPr(null)?.copy();
    if (end != null) {
      out.children.add(
        end.name.local == 'endParaRPr'
            ? end
            : XmlElement(XmlName.parts('endParaRPr', prefix: a), <XmlAttribute>[
                for (final at in end.attributes) at.copy(),
              ], <XmlNode>[for (final c in end.children) c.copy()]),
      );
    }
    return out;
  }

  /// Sets or clears an attribute, keeping its place among the others.
  static void _set(XmlElement e, String local, String? value) {
    final held = e.attributes.where((at) => at.name.local == local && at.name.prefix == null).firstOrNull;
    if (held != null && value != null) {
      held.value = value;
      return;
    }
    e.attributes.removeWhere((at) => at.name.local == local && at.name.prefix == null);
    if (value != null) e.attributes.add(XmlAttribute(XmlName.parts(local), value));
  }

  /// The children of `a:rPr` in the order the format keeps them.
  static const List<String> _rPrOrder = <String>[
    'ln',
    'noFill',
    'solidFill',
    'gradFill',
    'blipFill',
    'pattFill',
    'grpFill',
    'effectLst',
    'effectDag',
    'highlight',
    'uLnTx',
    'uLn',
    'uFillTx',
    'uFill',
    'latin',
    'ea',
    'cs',
    'sym',
    'hlinkClick',
    'hlinkMouseOver',
    'rtl',
    'extLst',
  ];

  /// The run properties for characters with [attrs], built from [template]
  /// where there is one: what the template already says is kept wherever
  /// the characters still look that way, and only what changed is said.
  XmlElement _runProperties(
    XmlDocument doc,
    String a,
    XmlElement? template,
    SlideTextLook was,
    SlideTextLook base,
    Map<String, dynamic> attrs,
  ) {
    final rPr = template == null
        ? XmlElement(XmlName.parts('rPr', prefix: a), <XmlAttribute>[XmlAttribute(XmlName.parts('lang'), 'en-US')])
        : XmlElement(
            XmlName.parts('rPr', prefix: a),
            <XmlAttribute>[for (final at in template.attributes) at.copy()],
            <XmlNode>[for (final c in template.children) c.copy()],
          );
    rPr.attributes.removeWhere((at) => at.name.local == 'dirty' || at.name.local == 'err');

    void flag(String key, String attr, bool wasOn, bool baseOn, String onValue, String offValue) {
      final want = attrs.containsKey(key) ? attrs[key] == true : baseOn;
      if (want == wasOn) return;
      _set(rPr, attr, want == baseOn ? null : (want ? onValue : offValue));
    }

    flag('bold', 'b', was.bold, base.bold, '1', '0');
    flag('italic', 'i', was.italic, base.italic, '1', '0');
    flag('underline', 'u', was.underline, base.underline, 'sng', 'none');
    final struck = template != null && _struck(template);
    final strike = attrs['strike'] == true;
    if (strike != struck) _set(rPr, 'strike', strike ? 'sngStrike' : null);
    final script = attrs['script'] as String?;
    if (script != _script(template)) {
      _set(rPr, 'baseline', switch (script) {
        'super' => '30000',
        'sub' => '-25000',
        _ => null,
      });
    }
    final size = double.tryParse('${attrs['size'] ?? ''}') ?? base.size;
    if ((size - was.size).abs() > 0.01) {
      _set(rPr, 'sz', (size - base.size).abs() < 0.01 ? null : '${(size * 100).round()}');
    }
    final colour = attrs['color'] is String ? int.tryParse((attrs['color'] as String).replaceFirst('#', ''), radix: 16) : null;
    final wasColour = (was.colour ?? 0xFF000000) & 0xFFFFFF;
    final wantColour = colour ?? ((base.colour ?? 0xFF000000) & 0xFFFFFF);
    if (wantColour != wasColour) {
      for (final c in rPr.childElements.toList()) {
        if (const <String>{'noFill', 'solidFill', 'gradFill', 'blipFill', 'pattFill', 'grpFill'}.contains(c.name.local)) {
          c.remove();
        }
      }
      if (colour != null) {
        final fill = XmlElement(XmlName.parts('solidFill', prefix: a), const <XmlAttribute>[], <XmlNode>[
          XmlElement(XmlName.parts('srgbClr', prefix: a), <XmlAttribute>[
            XmlAttribute(XmlName.parts('val'), colour.toRadixString(16).padLeft(6, '0').toUpperCase()),
          ]),
        ]);
        final rank = _rPrOrder.indexOf('solidFill');
        final at = rPr.children.indexWhere((n) => n is XmlElement && _rPrOrder.indexOf(n.name.local) > rank);
        if (at < 0) {
          rPr.children.add(fill);
        } else {
          rPr.children.insert(at, fill);
        }
      }
    }
    return rPr;
  }
}
