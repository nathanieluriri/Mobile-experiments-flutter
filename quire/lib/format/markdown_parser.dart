import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../model/document.dart';

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
    final doc = md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    );
    final nodes = doc.parseLines(const LineSplitter().convert(source));
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

