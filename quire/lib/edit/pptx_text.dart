import 'package:xml/xml.dart';

import '../format/pptx_parser.dart';
import '../model/document.dart';
import 'docx_delta.dart' show alignText;
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

/// The run a character of a written line takes its properties from.
class _Base {
  const _Base(this.read, this.run, {this.linked = true});
  final _Read read;
  final int run;

  /// False for a character typed beside a run rather than inside it, which
  /// the run's link does not reach.
  final bool linked;

  bool sameRun(_Base other) => identical(read, other.read) && run == other.run;
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
    final (pairs, joins) = _pair(lines);
    // Every line belongs to the paragraph of the paired line before it: a
    // line split off a paragraph, or typed after it, takes after it.
    final owner = List<int?>.filled(lines.length, null);
    int? current;
    for (var i = 0; i < lines.length; i++) {
      if (pairs[i] != null) current = i;
      owner[i] = current;
    }
    final first = pairs.indexWhere((p) => p != null);
    for (var i = 0; i < first; i++) {
      owner[i] = first;
    }
    final bases = _bases(lines, pairs, joins, owner);
    for (var i = 0; i < lines.length; i++) {
      final source = pairs[i];
      final read = source == null ? null : _paragraphs[source];
      if (read != null && !joins.containsKey(i) && _same(read.line, lines[i])) {
        out.children.add(read.element.copy());
        continue;
      }
      final template = owner[i] == null ? _paragraphs.firstOrNull : _paragraphs[pairs[owner[i]!]!];
      out.children.add(_paragraph(doc, a, lines[i], template, bases[i]));
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

  /// For each new line, the paragraph it was read from, if any, and for a
  /// line that joined paragraphs, the ones after it that it took in.
  /// Lines that are unchanged anchor the pairing; the lines between two
  /// anchors pair with the paragraphs between them they share the most with,
  /// one for one, one paragraph split into lines, or lines joined into one.
  (List<int?>, Map<int, List<int>>) _pair(List<List<Map<String, dynamic>>> lines) {
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
    final joins = <int, List<int>>{};
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
    var lastOld = -1, lastNew = -1;
    for (final (ao, an) in <(int, int)>[...anchors, (n, m)]) {
      _pairGap(
        lines,
        <int>[for (var k = lastOld + 1; k < ao; k++) k],
        <int>[for (var k = lastNew + 1; k < an; k++) k],
        out,
        joins,
      );
      lastOld = ao;
      lastNew = an;
    }
    return (out, joins);
  }

  /// The most paragraphs one line may join, or lines one paragraph split
  /// into, that the pairing looks for.
  static const int _most = 3;

  void _pairGap(
    List<List<Map<String, dynamic>>> lines,
    List<int> olds,
    List<int> news,
    List<int?> out,
    Map<int, List<int>> joins,
  ) {
    final n = olds.length, m = news.length;
    if (n == 0 || m == 0) return;
    if (n * m > 40000) {
      for (var k = 0; k < n && k < m; k++) {
        out[news[k]] = olds[k];
      }
      return;
    }
    final texts = <String>[for (final l in news) _textOf(lines[l])];
    // A pair is worth one for being a pair, so lines that share nothing
    // with their paragraphs still pair one for one, and one more for each
    // character the two share at their ends.
    int worth(int x, int k, int y, int l) => 1 +
        _shared(
          <String>[for (var c = x; c < x + k; c++) _paragraphs[olds[c]].text].join(),
          texts.sublist(y, y + l).join(),
        );
    final table = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    final pick = List<List<(int, int)>>.generate(n + 1, (_) => List<(int, int)>.filled(m + 1, (0, 0)));
    for (var x = n - 1; x >= 0; x--) {
      for (var y = m - 1; y >= 0; y--) {
        var best = worth(x, 1, y, 1) + table[x + 1][y + 1];
        var choice = (1, 1);
        if (table[x + 1][y] > best) {
          best = table[x + 1][y];
          choice = (1, 0);
        }
        if (table[x][y + 1] > best) {
          best = table[x][y + 1];
          choice = (0, 1);
        }
        // A join or a split has to share more than any plainer reading.
        for (var k = 2; k <= _most && x + k <= n; k++) {
          final total = worth(x, k, y, 1) + table[x + k][y + 1];
          if (total > best) {
            best = total;
            choice = (k, 1);
          }
        }
        for (var l = 2; l <= _most && y + l <= m; l++) {
          final total = worth(x, 1, y, l) + table[x + 1][y + l];
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
      if (k > 0 && l > 0) {
        out[news[y]] = olds[x];
        if (k > 1) joins[news[y]] = <int>[for (var c = x + 1; c < x + k; c++) olds[c]];
      }
      x += k;
      y += l;
    }
  }

  /// How many characters [a] and [b] share at their starts and their ends,
  /// the cheap measure of kinship.
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

  /// For each character of each line, the run it takes its properties
  /// from. The lines of one paragraph, and the paragraphs a line joined,
  /// are lined up as one: a character kept takes its own run, wherever it
  /// went, and one typed takes the run of the character kept before it, or
  /// after it at a line's start, without the link of a run it only stands
  /// beside.
  List<List<_Base?>> _bases(
    List<List<Map<String, dynamic>>> lines,
    List<int?> pairs,
    Map<int, List<int>> joins,
    List<int?> owner,
  ) {
    final out = <List<_Base?>>[
      for (final l in lines) List<_Base?>.filled(_textOf(l).length, null),
    ];
    var i = 0;
    while (i < lines.length) {
      final o = owner[i];
      var end = i + 1;
      while (end < lines.length && owner[end] == o) {
        end++;
      }
      if (o != null) {
        final olds = <_Read>[_paragraphs[pairs[o]!], for (final k in joins[o] ?? const <int>[]) _paragraphs[k]];
        final oldBases = <_Base?>[];
        for (var k = 0; k < olds.length; k++) {
          if (k > 0) oldBases.add(null);
          final read = olds[k];
          for (var c = 0; c < read.text.length; c++) {
            oldBases.add(c < read.sources.length ? _Base(read, read.sources[c]) : null);
          }
        }
        final at = <(int, int)>[];
        final texts = <String>[];
        for (var k = i; k < end; k++) {
          final text = _textOf(lines[k]);
          if (k > i) at.add((-1, -1));
          for (var c = 0; c < text.length; c++) {
            at.add((k, c));
          }
          texts.add(text);
        }
        final kept = alignText(<String>[for (final r in olds) r.text].join('\n'), texts.join('\n'));
        final found = List<_Base?>.generate(
          kept.length,
          (k) => kept[k] >= 0 && kept[k] < oldBases.length && at[k].$1 >= 0 ? oldBases[kept[k]] : null,
        );
        final after = List<_Base?>.filled(found.length, null);
        final afterLine = List<int>.filled(found.length, -1);
        _Base? next;
        var nextLine = -1;
        for (var k = found.length - 1; k >= 0; k--) {
          after[k] = next;
          afterLine[k] = nextLine;
          if (found[k] != null) {
            next = found[k];
            nextLine = at[k].$1;
          }
        }
        _Base? before;
        var beforeLine = -1;
        for (var k = 0; k < found.length; k++) {
          final (line, c) = at[k];
          if (line < 0) continue;
          final own = found[k];
          if (own != null) {
            out[line][c] = own;
            before = own;
            beforeLine = line;
            continue;
          }
          final take = before ?? after[k];
          if (take == null) continue;
          // A character typed between two of one run's is inside it, link
          // and all; one typed at a run's edge is not in its link.
          final inside = before != null &&
              after[k] != null &&
              before.sameRun(after[k]!) &&
              beforeLine == line &&
              afterLine[k] == line;
          out[line][c] = inside ? take : _Base(take.read, take.run, linked: false);
        }
      }
      i = end;
    }
    return out;
  }

  /// A paragraph written from [line], with the paragraph properties of
  /// [template], the paragraph it was read from or takes after, and each
  /// character's run properties from its entry in [bases].
  XmlElement _paragraph(
    XmlDocument doc,
    String a,
    List<Map<String, dynamic>> line,
    _Read? template,
    List<_Base?> bases,
  ) {
    XmlElement el(String local, [Map<String, String> attributes = const <String, String>{}, List<XmlNode> children = const <XmlNode>[]]) =>
        XmlElement(XmlName.parts(local, prefix: a), <XmlAttribute>[
          for (final e in attributes.entries) XmlAttribute(XmlName.parts(e.key), e.value),
        ], children);

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
    final chars = <(String, Map<String, dynamic>, Object?)>[];
    for (final op in line) {
      final insert = op['insert'];
      final attrs = op['attributes'] is Map ? Map<String, dynamic>.from(op['attributes'] as Map) : <String, dynamic>{};
      if (insert is String) {
        if (insert == '\n') continue;
        for (final ch in insert.runes) {
          // A vertical tab is the line break of text copied from PowerPoint
          // or Word; other control characters cannot be written in XML.
          final s = ch == 0x0B
              ? kSlideBreak
              : (ch < 0x20 && ch != 0x09) || ch == 0xFFFE || ch == 0xFFFF
              ? ''
              : String.fromCharCode(ch);
          for (var u = 0; u < (ch > 0xFFFF ? 2 : 1); u++) {
            chars.add((u == 0 ? s : '', attrs, null));
          }
        }
      } else if (insert is Map) {
        chars.add(('\uFFFC', attrs, insert[kSlideKept]));
      }
    }

    final runs = template?.runs ?? const <(XmlElement, SlideTextLook)>[];
    final endProperties = template == null ? null : _kid(template.element, 'endParaRPr');
    XmlElement? templateRPr(_Base? base) {
      if (base != null && base.run < base.read.runs.length) return _kid(base.read.runs[base.run].$1, 'rPr');
      final first = runs.where((r) => r.$1.name.local == 'r').firstOrNull;
      return (first == null ? null : _kid(first.$1, 'rPr')) ?? endProperties;
    }

    SlideTextLook lookOf(_Base? base) {
      if (base != null && base.run < base.read.runs.length) return base.read.runs[base.run].$2;
      return runs.isEmpty ? was : runs.first.$2;
    }

    XmlElement properties(_Base? at, Map<String, dynamic> attrs) {
      final rPr = _runProperties(doc, a, templateRPr(at), lookOf(at), base, attrs);
      if (at == null || !at.linked) _unlink(rPr);
      return rPr;
    }

    bool together(_Base? x, _Base? y) =>
        x == null ? y == null : y != null && x.sameRun(y) && x.linked == y.linked;

    var i = 0;
    while (i < chars.length) {
      final (ch, attrs, key) = chars[i];
      final at = i < bases.length ? bases[i] : null;
      if (key != null) {
        final element = kept[key];
        if (element != null) out.children.add(element.copy());
        i++;
        continue;
      }
      if (ch == kSlideBreak) {
        out.children.add(el('br', const <String, String>{}, <XmlNode>[properties(at, attrs)]));
        i++;
        continue;
      }
      final buffer = StringBuffer(ch);
      var j = i + 1;
      while (j < chars.length &&
          chars[j].$3 == null &&
          chars[j].$1 != kSlideBreak &&
          together(j < bases.length ? bases[j] : null, at) &&
          _canon(chars[j].$2) == _canon(attrs)) {
        buffer.write(chars[j].$1);
        j++;
      }
      if (buffer.isNotEmpty) {
        out.children.add(
          el('r', const <String, String>{}, <XmlNode>[
            properties(at, attrs),
            el('t', const <String, String>{}, <XmlNode>[XmlText(buffer.toString())]),
          ]),
        );
      }
      i = j;
    }
    final end = endProperties?.copy() ?? templateRPr(null)?.copy();
    if (end != null) {
      _unlink(end);
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

  static void _unlink(XmlElement rPr) {
    for (final c in rPr.childElements.toList()) {
      if (c.name.local == 'hlinkClick' || c.name.local == 'hlinkMouseOver') c.remove();
    }
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
