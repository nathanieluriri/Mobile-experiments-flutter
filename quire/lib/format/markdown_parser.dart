import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../model/document.dart';

/// The deepest a Markdown file may nest its lists and quotes.
///
/// The markdown package re-reads every line once for each container it sits
/// in, so its cost grows with the nesting times the length of the file. Two
/// thousand nested list items, the four megabytes a documentation generator
/// can emit, ran for nearly five minutes and never finished, and a hang is the
/// one failure nothing can catch: the app stops answering and the system kills
/// it. Measured here, a list 1200 deep took 7.8s and 2000 took 36s.
///
/// People write lists three or four deep, and eight is already unusual. The
/// count is taken from the source before the package sees it, since by the
/// time the tree exists the time is already spent, and it counts two columns
/// of indentation as a level, which overstates four space indents by double.
/// Past the limit the file is refused with a `FormatException`, which the
/// loader already turns into the damaged state the app draws.
const kMaxMarkdownNesting = 64;

/// CommonMark plus GFM into [QuireDocument], walking the markdown package's
/// own AST.
///
/// The AST already carries everything a reader needs, so nothing here re
/// implements a parser: the work is only mapping tags onto blocks and keeping
/// heading anchors unique, which is what makes the outline addressable.
class MarkdownParser {
  MarkdownParser(this.source);
  final String source;

  final List<OutlineEntry> _outline = [];
  final Map<String, int> _anchors = {};

  QuireDocument parse({String title = 'Document'}) {
    final lines = const LineSplitter().convert(source);
    for (final line in lines) {
      if (nestingOf(line) > kMaxMarkdownNesting) {
        throw const FormatException(
          'This file nests its lists or quotes more than '
          '$kMaxMarkdownNesting deep, further than it can be read.',
        );
      }
    }
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    );
    final nodes = doc.parseLines(lines);
    final blocks = <DocBlock>[];
    for (final n in nodes) {
      _block(n, blocks, 0);
    }
    return QuireDocument(
      title: title,
      sections: [DocSection(title, blocks)],
      sourceFormat: 'md',
      outline: _outline,
    );
  }

  /// An upper bound on how many lists and quotes [line] sits inside: half its
  /// indentation in columns, plus every marker that opens one at its start.
  /// Indentation alone counts only ahead of a marker, so a deeply indented
  /// line of code is not mistaken for nesting.
  static int nestingOf(String line) {
    var i = 0;
    var column = 0;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c == 0x20) {
        column++;
      } else if (c == 0x09) {
        column += 4 - column % 4;
      } else {
        break;
      }
      i++;
    }
    var markers = 0;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      var end = i;
      if (c == 0x3E) {
        end = i + 1;
      } else if (c == 0x2D || c == 0x2A || c == 0x2B) {
        end = i + 1;
        if (end < line.length && !_isSpace(line.codeUnitAt(end))) break;
      } else if (c >= 0x30 && c <= 0x39) {
        end = i;
        while (end < line.length && end - i < 9) {
          final d = line.codeUnitAt(end);
          if (d < 0x30 || d > 0x39) break;
          end++;
        }
        if (end >= line.length) break;
        final d = line.codeUnitAt(end);
        if (d != 0x2E && d != 0x29) break;
        end++;
        if (end < line.length && !_isSpace(line.codeUnitAt(end))) break;
      } else {
        break;
      }
      markers++;
      i = end;
      while (i < line.length && _isSpace(line.codeUnitAt(i))) {
        i++;
      }
    }
    return markers == 0 ? 0 : column ~/ 2 + markers;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x09;

  String _slug(String text) {
    var s = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (s.isEmpty) s = 'section';
    final n = _anchors.update(s, (v) => v + 1, ifAbsent: () => 0);
    return n == 0 ? s : '$s-$n';
  }

  void _block(md.Node node, List<DocBlock> out, int listLevel) {
    if (node is md.Text) {
      final t = node.text.trim();
      if (t.isNotEmpty) out.add(ParagraphBlock([DocSpan(t)]));
      return;
    }
    if (node is! md.Element) return;

    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        final spans = _inline(node.children ?? const []);
        final text = spans.map((s) => s.text).join();
        final anchor = _slug(text);
        _outline.add(OutlineEntry(text, level, 0, out.length));
        out.add(HeadingBlock(level, spans, anchor: anchor));
      case 'p':
        // A paragraph that is nothing but one image becomes an image block.
        final kids = (node.children ?? const <md.Node>[])
            .where((n) => !(n is md.Text && n.text.trim().isEmpty))
            .toList();
        if (kids.length == 1 &&
            kids.first is md.Element &&
            (kids.first as md.Element).tag == 'img') {
          final img = kids.first as md.Element;
          out.add(ImageBlock(img.attributes['src'] ?? '',
              alt: img.attributes['alt']));
          return;
        }
        final spans = _inline(node.children ?? const []);
        if (spans.isNotEmpty) out.add(ParagraphBlock(spans));
      case 'hr':
        out.add(const DividerBlock());
      case 'pre':
        final code = (node.children ?? const []).whereType<md.Element>().
            firstWhere((e) => e.tag == 'code',
                orElse: () => md.Element.text('code', node.textContent));
        final cls = code.attributes['class'] ?? '';
        final lang = cls.startsWith('language-') ? cls.substring(9) : null;
        out.add(CodeBlock(code.textContent.trimRight(), language: lang));
      case 'blockquote':
        final inner = <DocBlock>[];
        for (final c in node.children ?? const <md.Node>[]) {
          _block(c, inner, listLevel);
        }
        for (final b in inner) {
          if (b is ParagraphBlock) {
            out.add(ParagraphBlock(b.spans, align: b.align, quote: true));
          } else {
            out.add(b);
          }
        }
      case 'ul' || 'ol':
        final ordered = node.tag == 'ol';
        var index = int.tryParse(node.attributes['start'] ?? '1') ?? 1;
        for (final li in node.children ?? const <md.Node>[]) {
          if (li is! md.Element || li.tag != 'li') continue;
          _listItem(li, out, listLevel, ordered, index);
          index++;
        }
      case 'table':
        out.add(_table(node));
      case 'img':
        out.add(ImageBlock(node.attributes['src'] ?? '',
            alt: node.attributes['alt']));
      default:
        for (final c in node.children ?? const <md.Node>[]) {
          _block(c, out, listLevel);
        }
    }
  }

  void _listItem(
      md.Element li, List<DocBlock> out, int level, bool ordered, int index) {
    final leading = <md.Node>[];
    final nested = <md.Node>[];
    bool? checked;
    for (final c in li.children ?? const <md.Node>[]) {
      if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
        nested.add(c);
      } else if (c is md.Element && c.tag == 'input') {
        checked = c.attributes['checked'] == 'true' ||
            c.attributes.containsKey('checked');
      } else if (c is md.Element && c.tag == 'p') {
        leading.addAll(c.children ?? const []);
      } else {
        leading.add(c);
      }
    }
    final spans = _inline(leading);
    out.add(ListItemBlock(
      spans,
      level: level,
      ordered: ordered,
      marker: ordered ? '$index.' : (level == 0 ? '•' : '◦'),
      checked: checked,
    ));
    for (final n in nested) {
      _block(n, out, level + 1);
    }
  }

  TableBlock _table(md.Element table) {
    final rows = <DocRow>[];
    final aligns = <DocAlign?>[];
    for (final part in table.children ?? const <md.Node>[]) {
      if (part is! md.Element) continue;
      final header = part.tag == 'thead';
      for (final tr in part.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <DocCell>[];
        var col = 0;
        for (final td in tr.children ?? const <md.Node>[]) {
          if (td is! md.Element) continue;
          final a = switch (td.attributes['align']) {
            'center' => DocAlign.center,
            'right' => DocAlign.end,
            'left' => DocAlign.start,
            _ => null,
          };
          if (header) aligns.add(a);
          final align = a ?? (col < aligns.length ? aligns[col] : null);
          cells.add(DocCell(
            [
              ParagraphBlock(_inline(td.children ?? const []),
                  align: align ?? DocAlign.start)
            ],
            align: align,
          ));
          col++;
        }
        rows.add(DocRow(cells, header: header));
      }
    }
    return TableBlock(rows,
        columns: aligns.map((a) => DocColumn(align: a)).toList(),
        frozenRows: rows.isNotEmpty && rows.first.header ? 1 : 0);
  }

  List<DocSpan> _inline(List<md.Node> nodes) {
    final out = <DocSpan>[];
    _inlineInto(nodes, out,
        bold: false,
        italic: false,
        strike: false,
        mono: false,
        href: null);
    return out;
  }

  void _inlineInto(
    List<md.Node> nodes,
    List<DocSpan> out, {
    required bool bold,
    required bool italic,
    required bool strike,
    required bool mono,
    required String? href,
  }) {
    for (final n in nodes) {
      if (n is md.Text) {
        final t = n.text;
        if (t.isEmpty) continue;
        out.add(DocSpan(t,
            bold: bold,
            italic: italic,
            strike: strike,
            mono: mono,
            href: href));
        continue;
      }
      if (n is! md.Element) continue;
      switch (n.tag) {
        case 'strong':
          _inlineInto(n.children ?? const [], out,
              bold: true, italic: italic, strike: strike, mono: mono, href: href);
        case 'em':
          _inlineInto(n.children ?? const [], out,
              bold: bold, italic: true, strike: strike, mono: mono, href: href);
        case 'del':
          _inlineInto(n.children ?? const [], out,
              bold: bold, italic: italic, strike: true, mono: mono, href: href);
        case 'code':
          out.add(DocSpan(n.textContent,
              bold: bold, italic: italic, strike: strike, mono: true, href: href));
        case 'a':
          _inlineInto(n.children ?? const [], out,
              bold: bold,
              italic: italic,
              strike: strike,
              mono: mono,
              href: n.attributes['href']);
        case 'br':
          out.add(const DocSpan('\n'));
        case 'img':
          final alt = n.attributes['alt'] ?? '';
          if (alt.isNotEmpty) {
            out.add(DocSpan(alt, italic: true, href: n.attributes['src']));
          }
        case 'input':
          break; // task checkbox, handled by the list item
        default:
          _inlineInto(n.children ?? const [], out,
              bold: bold, italic: italic, strike: strike, mono: mono, href: href);
      }
    }
  }
}

