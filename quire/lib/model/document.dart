/// The single model every format parses into.
///
/// It exists so the renderer, the search and the fold all speak one language:
/// a docx paragraph, a Markdown heading, a spreadsheet cell and a PDF's text
/// layer are the same shapes here, which is what lets one back layer serve
/// every format. Nothing in this file imports Flutter, so a parser costs
/// nothing to unit test.
library;

import 'dart:typed_data';

/// Where a paragraph or a cell sits inside its measure.
enum DocAlign { start, center, end, justify }

/// A run of text sharing one set of character properties.
///
/// The properties are the union of what the four parsers can actually prove
/// from their sources. A parser that cannot tell leaves a field at its default
/// rather than guessing, so a renderer never inherits a lie.
class DocSpan {
  const DocSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.color,
    this.highlight,
    this.fontSize,
    this.href,
    this.script = 0,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool mono;

  /// 0xAARRGGBB, or null to inherit the body ink.
  final int? color;

  /// 0xAARRGGBB behind the glyphs, or null.
  final int? highlight;

  /// Logical points. Null means inherit from the block's style.
  final double? fontSize;

  /// Link target, or null.
  final String? href;

  /// -1 subscript, 0 normal, 1 superscript.
  final int script;

  /// Replaces the text and keeps every property, which is what a search
  /// highlighter needs when it splits one span into three.
  DocSpan copyWith({String? text}) => DocSpan(
        text ?? this.text,
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
        mono: mono,
        color: color,
        highlight: highlight,
        fontSize: fontSize,
        href: href,
        script: script,
      );

  @override
  String toString() {
    final flags = <String>[
      if (bold) 'b',
      if (italic) 'i',
      if (underline) 'u',
      if (strike) 's',
      if (mono) 'code',
      if (script == 1) 'sup',
      if (script == -1) 'sub',
      if (href != null) 'link',
    ];
    final body = text.replaceAll('\n', r'\n');
    return '"$body"${flags.isEmpty ? '' : ' [${flags.join(',')}]'}';
  }
}

/// One block in reading order. Sealed so a renderer's switch is exhaustive and
/// adding a block kind breaks the build instead of silently painting nothing.
sealed class DocBlock {
  const DocBlock();
}

/// Body text, a quotation, or an indented paragraph.
class ParagraphBlock extends DocBlock {
  const ParagraphBlock(
    this.spans, {
    this.align = DocAlign.start,
    this.indent = 0,
    this.quote = false,
    this.styleId,
  });
  final List<DocSpan> spans;
  final DocAlign align;

  /// Indent steps, each one half inch of the source's left indent.
  final int indent;
  final bool quote;

  /// The source's own style name, kept so the back of a Word page can print it
  /// in the margin.
  final String? styleId;

  String get text => spans.map((s) => s.text).join();
}

/// A heading at level 1 to 6.
class HeadingBlock extends DocBlock {
  const HeadingBlock(this.level, this.spans, {this.anchor});
  final int level;
  final List<DocSpan> spans;

  /// Markdown slug, or null for sources that have no anchors.
  final String? anchor;

  String get text => spans.map((s) => s.text).join();
}

/// One item of a bulleted, numbered or task list.
class ListItemBlock extends DocBlock {
  const ListItemBlock(
    this.spans, {
    required this.level,
    required this.ordered,
    this.marker,
    this.checked,
  });
  final List<DocSpan> spans;

  /// Zero based nesting depth.
  final int level;
  final bool ordered;

  /// The resolved glyph from numbering.xml, or a rendered number.
  final String? marker;

  /// Markdown task lists only. Null means this is not a task.
  final bool? checked;

  String get text => spans.map((s) => s.text).join();
}

/// A preformatted block, kept as raw text so no inline parse can reflow it.
class CodeBlock extends DocBlock {
  const CodeBlock(this.text, {this.language});
  final String text;
  final String? language;
}

/// A horizontal rule.
class DividerBlock extends DocBlock {
  const DividerBlock();
}

/// A picture. The bytes live in [QuireDocument.assets] rather than here, so a
/// block list stays cheap to copy and to walk for search.
class ImageBlock extends DocBlock {
  const ImageBlock(this.assetKey, {this.width, this.height, this.alt});

  /// Key into [QuireDocument.assets].
  final String assetKey;

  /// Logical points from the source, or null when the source is silent.
  final double? width;
  final double? height;
  final String? alt;
}

/// A column's intrinsic width and default alignment.
class DocColumn {
  const DocColumn({this.width, this.align});

  /// Logical points. Null means the renderer picks.
  final double? width;
  final DocAlign? align;
}

/// One cell. A cell holds blocks rather than a string, which is what lets a
/// Word table nest a table and lets a spreadsheet cell carry its own alignment
/// without a second model.
class DocCell {
  const DocCell(
    this.blocks, {
    this.colSpan = 1,
    this.rowSpan = 1,
    this.merged = false,
    this.align,
    this.background,
    this.numeric = false,
    this.raw,
    this.formula,
    this.comment,
    this.commentBy,
  });
  final List<DocBlock> blocks;
  final int colSpan;
  final int rowSpan;

  /// True when this cell is swallowed by a span that starts elsewhere. The
  /// renderer draws nothing and the search skips it.
  final bool merged;
  final DocAlign? align;
  final int? background;

  /// What somebody said about this cell, and who said it.
  ///
  /// A spreadsheet is often argued over in its margins, and a reader who
  /// cannot see the argument is reading half the document. Both are null for
  /// a cell nobody has discussed.
  final String? comment;
  final String? commentBy;

  /// Right align plus tabular figures.
  final bool numeric;

  /// The value before formatting: num, bool, DateTime or String.
  ///
  /// Keeping it beside [text] is what lets the back of a sheet show what is
  /// stored while the front shows what the source would display.
  final Object? raw;

  /// The cached formula source without its leading equals sign, or null.
  ///
  /// A cell's formula and its cached value coexist in the file. Keeping both is
  /// the difference between showing a reader the number the sheet holds and
  /// showing them the text of a calculation they did not ask for.
  final String? formula;

  /// The formatted text of every block in the cell, one line each.
  String get text => blocks
      .map((b) => switch (b) {
            ParagraphBlock() => b.text,
            HeadingBlock() => b.text,
            ListItemBlock() => b.text,
            CodeBlock() => b.text,
            _ => '',
          })
      .join('\n');
}

/// One row of a table.
class DocRow {
  const DocRow(this.cells, {this.header = false, this.height});
  final List<DocCell> cells;
  final bool header;

  /// Logical points, or null for the renderer's default.
  final double? height;
}

/// A table, or a whole spreadsheet grid.
class TableBlock extends DocBlock {
  const TableBlock(
    this.rows, {
    this.columns = const [],
    this.frozenRows = 0,
    this.frozenColumns = 0,
    this.grid = false,
  });
  final List<DocRow> rows;
  final List<DocColumn> columns;
  final int frozenRows;
  final int frozenColumns;

  /// True for xlsx and csv. It is what tells the reader to use the spine table
  /// instead of a prose table.
  final bool grid;
}

/// A sheet name for xlsx, a document title otherwise.
class DocSection {
  const DocSection(this.title, this.blocks, {this.kind = 'body'});
  final String title;
  final List<DocBlock> blocks;

  /// 'body', 'sheet' or 'page'.
  final String kind;
}

/// One entry of the document's outline, pointing at the block it names.
class OutlineEntry {
  const OutlineEntry(this.title, this.level, this.sectionIndex, this.blockIndex);
  final String title;
  final int level;
  final int sectionIndex;
  final int blockIndex;
}

/// A parsed document, whatever it came from.
class QuireDocument {
  const QuireDocument({
    required this.title,
    required this.sections,
    this.assets = const {},
    this.sourceFormat = '',
    this.outline = const [],
  });
  final String title;
  final List<DocSection> sections;

  /// Embedded media keyed by its path inside the source container.
  final Map<String, Uint8List> assets;

  /// 'docx', 'xlsx', 'csv' or 'md'.
  final String sourceFormat;
  final List<OutlineEntry> outline;

  /// Every word in every block, which is what the desk colophon and
  /// `readingMinutes` count. Computed rather than stored so it can never drift
  /// away from the blocks it describes.
  int get wordCount {
    var total = 0;
    for (final section in sections) {
      total += _wordsInBlocks(section.blocks);
    }
    return total;
  }

  static int _wordsInBlocks(List<DocBlock> blocks) {
    var total = 0;
    for (final b in blocks) {
      switch (b) {
        case ParagraphBlock():
          total += countWords(b.text);
        case HeadingBlock():
          total += countWords(b.text);
        case ListItemBlock():
          total += countWords(b.text);
        case CodeBlock():
          total += countWords(b.text);
        case ImageBlock():
          total += b.alt == null ? 0 : countWords(b.alt!);
        case TableBlock():
          for (final row in b.rows) {
            for (final cell in row.cells) {
              if (cell.merged) continue;
              total += _wordsInBlocks(cell.blocks);
            }
          }
        case DividerBlock():
          break;
      }
    }
    return total;
  }
}

/// Words are runs of non whitespace. Deliberately crude and deliberately the
/// same rule everywhere, so two counts of the same text always agree.
int countWords(String text) {
  var count = 0;
  var inWord = false;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final isSpace = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
    if (isSpace) {
      inWord = false;
    } else if (!inWord) {
      inWord = true;
      count++;
    }
  }
  return count;
}
