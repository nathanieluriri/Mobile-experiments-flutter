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

/// Where a cell's words sit between its top and its bottom.
enum DocVerticalAlign { top, center, bottom }

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
  const HeadingBlock(this.level, this.spans, {this.anchor, this.align = DocAlign.start});
  final int level;
  final List<DocSpan> spans;
  final DocAlign align;

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
    this.align = DocAlign.start,
  });
  final List<DocSpan> spans;
  final DocAlign align;

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

/// A box on a slide, in the slide's own points with the origin at its top
/// left.
///
/// Not a [Rect] because nothing in this file may import Flutter, and a slide
/// parser has to run in a plain Dart test.
class SlideBox {
  const SlideBox(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is SlideBox &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'SlideBox($left, $top, $width, $height)';
}

/// A chart as a slide carries it: its kind and the values the file keeps
/// for it, which is enough to draw it when the file has no picture of it.
class SlideChart {
  const SlideChart({
    required this.kind,
    required this.categories,
    required this.series,
    this.title,
    this.stacked = false,
    this.legend = true,
  });

  /// 'col', 'bar', 'line', 'area', 'pie' or 'doughnut'.
  final String kind;
  final List<String> categories;
  final List<SlideSeries> series;
  final String? title;
  final bool stacked;
  final bool legend;
}

/// One series of a chart: its name, its values by category, and its colour
/// as 0xAARRGGBB.
class SlideSeries {
  const SlideSeries(this.name, this.values, this.colour, {this.colours = const <int>[]});
  final String name;
  final List<double?> values;
  final int colour;

  /// A pie's slice colours, by category.
  final List<int> colours;
}

/// What a shape was put on its slide to be.
///
/// PowerPoint says this itself, in the placeholder each shape claims, and it
/// is worth keeping: it is the difference between a line of text that is the
/// slide's title and a line that happens to be at the top. The outline, the
/// riffle and the thumbnail all want the title and none of them want to guess
/// at it from a font size.
enum SlideRole { title, body, picture, table, chart, other }

/// One shape on a slide: a box holding blocks, with whatever the file says
/// about the box itself.
///
/// A shape carries blocks rather than text for the same reason a table cell
/// does: a text box on a slide holds paragraphs, bullets, and sometimes a
/// picture, and a second model for slide text would be a second set of bugs.
class SlideShape {
  const SlideShape({
    required this.box,
    required this.blocks,
    this.role = SlideRole.other,
    this.fill,
    this.fillAsset,
    this.line,
    this.lineWidth = 0,
    this.verticalAlign,
    this.rotation = 0,
    this.inherited = false,
    this.id,
    this.geometry = 'rect',
    this.dash,
    this.shadow = false,
    this.opacity = 1,
    this.flipH = false,
    this.flipV = false,
    this.placeholder,
    this.own,
    this.textable = false,
    this.chart,
    this.brightness = 0,
    this.contrast = 0,
  });

  /// The chart the shape is, drawn from its values when the file keeps no
  /// picture of it.
  final SlideChart? chart;

  /// A picture's brightness and contrast, each from -1 to 1.
  final double brightness;
  final double contrast;

  final SlideBox box;

  /// The shape's own id on its slide, which differs from [id] for a shape
  /// inside a group.
  final int? own;

  /// True for a shape words can be typed into.
  final bool textable;
  final List<DocBlock> blocks;
  final SlideRole role;

  /// The id the file gives the shape on its slide, or the id of the group it
  /// sits in, so an editor can tell which thing on the slide was touched.
  final int? id;

  /// The preset outline the shape is drawn in: 'rect', 'ellipse', 'line',
  /// 'roundRect', 'triangle' and the rest of PowerPoint's names.
  final String geometry;

  /// PowerPoint's name for the outline's dash, such as 'dash' or 'sysDot',
  /// or null for a solid line.
  final String? dash;

  /// True for a shape drawn with a drop shadow.
  final bool shadow;

  /// How opaque a picture is drawn, 0 to 1.
  final double opacity;

  final bool flipH;
  final bool flipV;

  /// The placeholder type of an empty placeholder kept so an editor can show
  /// where it is, such as 'title' or 'body'; null for any other shape.
  final String? placeholder;

  /// True for a shape the slide does not own: the rule, the running foot and
  /// the panels the layout and the master put on every slide.
  ///
  /// It is drawn like anything else, and it is skipped wherever a deck is
  /// read out rather than shown. A reader given the deck as text does not want
  /// the same running foot repeated once per slide.
  final bool inherited;

  /// 0xAARRGGBB behind the shape, or null for one that is not filled.
  final int? fill;

  /// Key into [QuireDocument.assets] for a shape filled with a picture, which
  /// is how a deck's decorated panels are usually made.
  final String? fillAsset;

  /// 0xAARRGGBB of the shape's outline, or null for one with no outline.
  final int? line;

  /// Logical points. Zero with no outline.
  final double lineWidth;

  /// Where the words sit between the box's top and its bottom.
  final DocVerticalAlign? verticalAlign;

  /// Clockwise degrees. Almost always zero, and ruinous when it is not and
  /// nobody kept it.
  final double rotation;

  SlideShape copyWith({
    SlideBox? box,
    List<DocBlock>? blocks,
    double? rotation,
    bool? inherited,
    int? id,
    bool? flipH,
    bool? flipV,
  }) => SlideShape(
    box: box ?? this.box,
    blocks: blocks ?? this.blocks,
    role: role,
    fill: fill,
    fillAsset: fillAsset,
    line: line,
    lineWidth: lineWidth,
    verticalAlign: verticalAlign,
    rotation: rotation ?? this.rotation,
    inherited: inherited ?? this.inherited,
    id: id ?? this.id,
    geometry: geometry,
    dash: dash,
    shadow: shadow,
    opacity: opacity,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    placeholder: placeholder,
    own: own,
    textable: textable,
    chart: chart,
    brightness: brightness,
    contrast: contrast,
  );

  /// Every word the shape holds, in order.
  String get text => blocks
      .map(
        (b) => switch (b) {
          ParagraphBlock() => b.text,
          HeadingBlock() => b.text,
          ListItemBlock() => b.text,
          CodeBlock() => b.text,
          _ => '',
        },
      )
      .where((line) => line.isNotEmpty)
      .join('\n');
}

/// One slide: its own canvas, the shapes on it, and what the speaker was going
/// to say.
///
/// A slide is laid out rather than flowed, which is why it is one block
/// carrying boxes instead of a run of paragraphs. [width] and [height] are the
/// deck's slide size in points, and every shape's box is inside them, so a
/// renderer scales the whole slide by one number and never has to measure
/// anything to know where a thing goes.
class SlideBlock extends DocBlock {
  const SlideBlock({
    required this.width,
    required this.height,
    required this.shapes,
    this.background,
    this.backgroundAsset,
    this.notes = const <DocBlock>[],
    this.layoutName,
  });

  /// The slide canvas in logical points.
  final double width;
  final double height;

  final List<SlideShape> shapes;

  /// 0xAARRGGBB of the slide's ground, or null for paper white.
  final int? background;

  /// Key into [QuireDocument.assets] for a slide whose ground is a picture.
  final String? backgroundAsset;

  /// The speaker notes, which are a document of their own and belong on the
  /// back of the sheet rather than on the slide.
  final List<DocBlock> notes;

  /// The layout the slide was built on, kept for the back of the sheet.
  final String? layoutName;

  SlideBlock withShapes(List<SlideShape> shapes) => SlideBlock(
    width: width,
    height: height,
    shapes: shapes,
    background: background,
    backgroundAsset: backgroundAsset,
    notes: notes,
    layoutName: layoutName,
  );

  /// The slide's own title, or null for one that has no title placeholder.
  String? get title {
    for (final shape in shapes) {
      if (shape.role != SlideRole.title) continue;
      final text = shape.text.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
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
    this.wrap = false,
    this.verticalAlign,
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

  /// True when the cell's words wrap onto as many lines as its width makes,
  /// rather than running on in one line.
  final bool wrap;

  /// Where the words sit up and down the cell, or null for the renderer's
  /// choice.
  final DocVerticalAlign? verticalAlign;

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
      .map(
        (b) => switch (b) {
          ParagraphBlock() => b.text,
          HeadingBlock() => b.text,
          ListItemBlock() => b.text,
          CodeBlock() => b.text,
          _ => '',
        },
      )
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
    this.defaultColumnWidth,
    this.defaultRowHeight,
  });
  final List<DocRow> rows;
  final List<DocColumn> columns;
  final int frozenRows;
  final int frozenColumns;

  /// The width a table gives a column it says nothing else about, and the
  /// height it gives such a row, in the same points as a column's own width
  /// and a row's own height. Null leaves them to the renderer.
  final double? defaultColumnWidth;
  final double? defaultRowHeight;

  /// True for xlsx and csv. It is what tells the reader to use the spine table
  /// instead of a prose table.
  final bool grid;
}

/// A sheet name for xlsx, a slide's own title for pptx, a document title
/// otherwise.
class DocSection {
  const DocSection(this.title, this.blocks, {this.kind = 'body'});
  final String title;
  final List<DocBlock> blocks;

  /// 'body', 'sheet', 'page' or 'slide'.
  final String kind;
}

/// One entry of the document's outline, pointing at the block it names.
class OutlineEntry {
  const OutlineEntry(
    this.title,
    this.level,
    this.sectionIndex,
    this.blockIndex,
  );
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

  /// 'docx', 'xlsx', 'pptx', 'csv' or 'md'.
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
        case SlideBlock():
          for (final shape in b.shapes) {
            total += _wordsInBlocks(shape.blocks);
          }
          // The notes are not on the slide. Counting them would tell a reader
          // a deck is twice the length they are about to read.
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
