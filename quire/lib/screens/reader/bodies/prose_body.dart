import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../services/document_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/easings.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/system_text_scale.dart';
import '../../../widgets/marked_text.dart';
import '../../../widgets/paragraph_marks.dart';
import '../back_layer.dart';
import 'deck_body.dart';
import '../find/find_layer.dart';
import '../sheet_surface.dart';
import 'page_states.dart';

/// How far one level of nesting or one level of indent moves text right.
const double kProseIndent = 22.0;

/// The gutter a list marker hangs in, wide enough for `12.` at the folio size.
const double kProseMarkerGutter = 18.0;

/// The bullet a plain list item hangs, and the box a task list item carries.
const double kProseBullet = 4.0;
const double kProseCheckBox = 15.0;
const double kProseCheckTick = 9.0;

/// The bar a quotation hangs on, and how far its text clears it.
const double kProseQuoteBar = 3.0;
const double kProseQuoteInset = 14.0;

/// A rule inside a document is a typographic full point, not a divider, so it
/// is drawn short and centred rather than across the measure.
const double kProseRuleFraction = 0.4;

/// How tall a picture is allowed to stand in the column, and how tall the rect
/// a missing one leaves behind is.
const double kProseImageMaxHeight = 320.0;
const double kProseMissingImageHeight = 160.0;

/// How much of the reading measure a table gives back, so a table reads as an
/// inset rather than as the column itself.
const double kProseTableScale = 0.9;

/// How far the first line of a fenced block sits below the slab's top edge
/// when the file named the language: the label's own line, plus its inset.
const double kCodeLanguageClearance = 22.0;

/// The style a heading of [block]'s level is set in.
///
/// Everything past the third level keeps the third level's size. A document
/// that nests six deep is telling you about its own structure, not about how
/// loud its sixth level should be, and a phone column has no room to say it.
TextStyle proseHeadingStyle(HeadingBlock block) => switch (block.level) {
  1 => AppText.pageHeading1,
  2 => AppText.pageHeading2,
  _ => AppText.pageHeading3,
};

/// The space a block asks for above itself.
double proseSpaceAbove(DocBlock block) => switch (block) {
  HeadingBlock(:final level) when level == 1 => 28,
  HeadingBlock(:final level) when level == 2 => 24,
  HeadingBlock() => 20,
  DividerBlock() => 24,
  ImageBlock() => 20,
  TableBlock() => 16,
  CodeBlock() => 12,
  _ => 0,
};

/// The space a block asks for below itself.
double proseSpaceBelow(DocBlock block) => switch (block) {
  HeadingBlock(:final level) when level == 1 => 10,
  HeadingBlock(:final level) when level == 2 => 8,
  HeadingBlock() => 6,
  DividerBlock() => 24,
  ImageBlock() => 20,
  TableBlock() => 16,
  CodeBlock() => 12,
  ListItemBlock() => 6,
  _ => 12,
};

/// The gap between two blocks that follow each other.
///
/// It is the larger of what one asks for below and the other asks for above,
/// never the sum. Adding them is how a heading after a paragraph ends up
/// forty points down the page and the document reads as a stack of cards
/// rather than as a column of prose.
double proseGap(DocBlock above, DocBlock below) =>
    proseSpaceBelow(above) > proseSpaceAbove(below)
    ? proseSpaceBelow(above)
    : proseSpaceAbove(below);

/// How one run inside a paragraph is set.
///
/// A document's own colours are deliberately dropped. This app has two accent
/// hues and each means one thing, found and you, so a file that sets its
/// subtitle in red would be claiming one of them. What the file actually
/// stored is on the back of the sheet, which is where it belongs.
TextStyle proseSpanStyle(DocSpan span, {TextStyle? base, Color? color}) {
  var style = (base ?? AppText.pageBody).copyWith(
    color: color ?? AppColors.inkSoft,
  );
  if (span.italic) {
    style = style.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.2);
  }
  // 600, never 700: 700 shouts in a reading column.
  if (span.bold) style = style.copyWith(fontWeight: FontWeight.w600);
  if (span.href != null) {
    style = style.copyWith(
      color: color ?? AppColors.ink,
      fontWeight: FontWeight.w500,
    );
  }
  final decorations = <TextDecoration>[
    if (span.underline || span.href != null) TextDecoration.underline,
    if (span.strike) TextDecoration.lineThrough,
  ];
  if (decorations.isEmpty) return style;
  return style.copyWith(
    decoration: TextDecoration.combine(decorations),
    // A link's rule is held one step under its text rather than down at the
    // rule colour, which on a dark sheet would be no rule at all and would
    // leave a link telling itself apart from body text by weight alone.
    decorationColor: span.href != null ? AppColors.inkFaint : style.color,
    decorationThickness: 1,
  );
}

/// A code span, on the slab that separates it from the prose around it.
///
/// There is no monospaced family in this bundle and none is added. The slab is
/// what says `this is literal`, which is the job the second family would have
/// been doing.
class MonoSpan extends StatelessWidget {
  const MonoSpan({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kInlineCodeRadius),
      ),
      child: Text(
        text,
        style: AppText.code.copyWith(color: AppColors.inkSoft),
      ),
    );
  }
}

/// The box a task list item carries, ticked or empty.
class CheckMark extends StatelessWidget {
  const CheckMark({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kProseCheckBox,
      height: kProseCheckBox,
      child: DecoratedBox(
        // An empty box is drawn in [AppColors.inkFaint], not in the rule
        // colour. A hairline is meant to be a whisper between two surfaces; a
        // box saying a job is not done yet has to be read, and at rule value
        // on a dark sheet it would be a smudge a reader could take for nothing
        // at all.
        decoration: BoxDecoration(
          color: checked ? AppColors.accent : null,
          border: Border.all(
            color: checked ? AppColors.accent : AppColors.inkFaint,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(kInlineCodeRadius),
        ),
        child: checked
            ? const Center(
                child: SizedBox(
                  width: kProseCheckTick,
                  height: kProseCheckTick,
                  child: CustomPaint(painter: _TickPainter()),
                ),
              )
            : null,
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.1, size.height * 0.55)
      ..lineTo(size.width * 0.4, size.height * 0.85)
      ..lineTo(size.width * 0.95, size.height * 0.15);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.onAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => false;
}

/// The bar a quotation hangs on. Quotation marks would be the document's own
/// punctuation; the bar is the reader's.
///
/// It is drawn in [AppColors.inkFaint] and not in the rule colour, because it
/// is the only thing saying a quotation is a quotation. A divider that goes
/// unnoticed has still divided; a quote bar that goes unnoticed has turned a
/// quotation into body text.
class QuoteBar extends StatelessWidget {
  const QuoteBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: kProseQuoteInset),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.inkFaint, width: kProseQuoteBar),
        ),
      ),
      child: child,
    );
  }
}

/// A fenced block, on its own slab, scrolling sideways inside its own clip so
/// the reading column never scrolls with it.
class CodeSlab extends StatelessWidget {
  const CodeSlab({
    super.key,
    required this.block,
    this.marks = const <BlockMark>[],
  });

  final CodeBlock block;

  /// What a find has turned up in the block, set as its own text is.
  final List<BlockMark> marks;

  @override
  Widget build(BuildContext context) {
    final language = block.language;
    final named = language != null && language.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kCodeRadius),
      ),
      child: Stack(
        children: [
          Padding(
            // The first line clears the language label rather than running
            // under it, because a fenced block's first line is usually the
            // one that says what the block is.
            padding: EdgeInsets.fromLTRB(
              kSpace12,
              named ? kCodeLanguageClearance : kSpace12,
              kSpace12,
              kSpace12,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ParagraphMarks(
                marks: <TextMark>[
                  for (final mark in marks)
                    if (mark.within.isEmpty)
                      TextMark(
                        start: mark.start,
                        end: mark.end,
                        fill: mark.fill,
                        color: mark.color,
                      ),
                ],
                markerColor: AppColors.foundWash,
                child: Text(
                  block.text,
                  style: AppText.code.copyWith(color: AppColors.inkSoft),
                ),
              ),
            ),
          ),
          if (named)
            Positioned(
              top: kSpace8,
              right: kSpace8,
              child: Text(
                language,
                style: AppText.micro.copyWith(color: AppColors.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

/// The short centred rule a document uses to mark a break in its own text.
class ProseRule extends StatelessWidget {
  const ProseRule({super.key, this.measure = kProseMeasure});

  final double measure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: measure * kProseRuleFraction,
        height: 1,
        child: const ColoredBox(color: AppColors.hairline),
      ),
    );
  }
}

/// A table inside flowing prose: the file's own columns, fitted to the
/// reading measure and set a step smaller than the text around it, inside a
/// hairline box so it reads as an inset rather than as the column itself.
class ProseTable extends StatelessWidget {
  const ProseTable({
    super.key,
    required this.table,
    this.measure = kProseMeasure,
    this.marks = const <BlockMark>[],
  });

  final TableBlock table;
  final double measure;

  /// What a find has turned up in the table's cells.
  final List<BlockMark> marks;

  @override
  Widget build(BuildContext context) {
    final columns = table.rows.fold<int>(
      0,
      (most, row) => row.cells.length > most ? row.cells.length : most,
    );
    if (columns == 0) return const SizedBox.shrink();
    final widths = _widths(columns, measure - 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline, width: 1),
        borderRadius: BorderRadius.circular(kCodeRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kCodeRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < table.rows.length; r++)
              _row(table.rows[r], r, widths),
          ],
        ),
      ),
    );
  }

  /// The file's own column widths, fitted to what the column has to give. A
  /// table that overflowed the measure would make the one thing this reader
  /// promises, a column you can read, the one thing it could not do.
  List<double> _widths(int columns, double available) {
    final declared = <double>[
      for (var c = 0; c < columns; c++)
        c < table.columns.length ? (table.columns[c].width ?? 0) : 0,
    ];
    final total = declared.fold<double>(0, (sum, w) => sum + w);
    if (total <= 0) {
      return List<double>.filled(columns, available / columns);
    }
    return <double>[
      for (final width in declared)
        width <= 0 ? available / columns : available * width / total,
    ];
  }

  Widget _row(DocRow row, int index, List<double> widths) {
    final leader = (index + 1) % kLeaderEvery == 0;
    return Container(
      constraints: BoxConstraints(
        minHeight: row.header
            ? kTableHeaderHeight * kProseTableScale
            : kTableRowHeight * kProseTableScale,
      ),
      decoration: BoxDecoration(
        color: row.header
            ? AppColors.surfaceHigh
            : (index.isOdd ? AppColors.leafBack : null),
        border: index == table.rows.length - 1
            ? null
            : Border(
                bottom: BorderSide(
                  color: row.header || leader
                      ? AppColors.hairline
                      : AppColors.hairlineFaint,
                  width: 1,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var c = 0; c < row.cells.length; c++)
            if (!row.cells[c].merged)
              SizedBox(
                width: _spanWidth(row.cells[c], c, widths),
                child: _cell(row.cells[c], row.header, c, index),
              ),
        ],
      ),
    );
  }

  double _spanWidth(DocCell cell, int index, List<double> widths) {
    var width = 0.0;
    for (var c = index; c < index + cell.colSpan && c < widths.length; c++) {
      width += widths[c];
    }
    return width;
  }

  Widget _cell(DocCell cell, bool header, int index, int row) {
    final align = cell.align ??
        (index < table.columns.length ? table.columns[index].align : null) ??
        (cell.numeric ? DocAlign.end : DocAlign.start);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kCellPaddingX,
        vertical: kSpace4,
      ),
      child: Align(
        alignment: switch (align) {
          DocAlign.center => Alignment.centerLeft,
          DocAlign.end => Alignment.centerRight,
          _ => Alignment.centerLeft,
        },
        child: ParagraphMarks(
          marks: _cellMarks(cell, row, index),
          markerColor: AppColors.foundWash,
          child: Text(
            cell.text,
            textAlign: align == DocAlign.center ? TextAlign.center : null,
            style: header
                ? AppText.cellHeader.copyWith(color: AppColors.ink)
                : AppText.cell.copyWith(color: AppColors.inkSoft),
          ),
        ),
      ),
    );
  }

  /// The strokes for one cell, moved from the offsets inside the cell's own
  /// block to the offsets in the cell's text, which sets its blocks one line
  /// each.
  List<TextMark> _cellMarks(DocCell cell, int row, int column) {
    if (marks.isEmpty) return const <TextMark>[];
    final out = <TextMark>[];
    for (final mark in marks) {
      final within = mark.within;
      if (within.length != 3 || within[0] != row || within[1] != column) {
        continue;
      }
      final before = lineStartOf(cell, within[2]);
      out.add(
        TextMark(
          start: before + mark.start,
          end: before + mark.end,
          fill: mark.fill,
          color: mark.color,
        ),
      );
    }
    return out;
  }

  /// Where the text of block [index] of [cell] starts in the cell's own text,
  /// which sets each of its blocks on a line of its own.
  static int lineStartOf(DocCell cell, int index) {
    var before = 0;
    for (var b = 0; b < index && b < cell.blocks.length; b++) {
      before += _lineOf(cell.blocks[b]).length + 1;
    }
    return before;
  }

  /// Which of [table]'s drawn cells, counted across and then down, is the cell
  /// at [row] and [column], or -1 for one swallowed by a span. A cell a span
  /// swallows is not drawn, so it is not counted.
  static int cellOrdinal(TableBlock table, int row, int column) {
    if (row < 0 || row >= table.rows.length) return -1;
    final cells = table.rows[row].cells;
    if (column < 0 || column >= cells.length || cells[column].merged) return -1;
    var ordinal = 0;
    for (var r = 0; r < row; r++) {
      for (final cell in table.rows[r].cells) {
        if (!cell.merged) ordinal++;
      }
    }
    for (var c = 0; c < column; c++) {
      if (!cells[c].merged) ordinal++;
    }
    return ordinal;
  }

  static String _lineOf(DocBlock block) => switch (block) {
    ParagraphBlock() => block.text,
    HeadingBlock() => block.text,
    ListItemBlock() => block.text,
    CodeBlock() => block.text,
    _ => '',
  };
}

/// One block of a document, in the reading column.
///
/// The switch is exhaustive over the sealed model, which is what the model is
/// sealed for: a block kind added to the document model cannot be forgotten
/// here, because the analyzer will not build until it is drawn.
class ProseBlockView extends StatelessWidget {
  const ProseBlockView({
    super.key,
    required this.block,
    this.assets = const <String, Uint8List>{},
    this.measure = kProseMeasure,
    this.foldBreaks = false,
    this.marks = const <BlockMark>[],
  });

  final DocBlock block;

  /// What a find has turned up in this block, for the highlighter.
  final List<BlockMark> marks;

  /// A document's own media, keyed by the path the file stored it under.
  final Map<String, Uint8List> assets;

  final double measure;

  /// True for a format whose line breaks inside a paragraph are only where
  /// the source file happened to wrap.
  final bool foldBreaks;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      HeadingBlock() => _heading(block as HeadingBlock),
      ParagraphBlock() => _paragraph(block as ParagraphBlock),
      ListItemBlock() => _listItem(block as ListItemBlock),
      CodeBlock() => CodeSlab(block: block as CodeBlock, marks: marks),
      DividerBlock() => ProseRule(measure: measure),
      ImageBlock() => _image(block as ImageBlock),
      TableBlock() => ProseTable(
        table: block as TableBlock,
        measure: measure,
        marks: marks,
      ),
      // A deck is read on its own bench, so this is only reached by a slide
      // that arrived inside another format. It keeps its own shape at the
      // measure rather than being unpacked into paragraphs.
      SlideBlock() => SlideCard(
        slide: block as SlideBlock,
        assets: assets,
        width: measure,
      ),
    };
  }

  Widget _heading(HeadingBlock block) => _marked(
    block.spans,
    Text.rich(
      proseSpansOf(
        block.spans,
        base: proseHeadingStyle(block),
        color: AppColors.ink,
        foldBreaks: foldBreaks,
      ),
      style: proseHeadingStyle(block).copyWith(color: AppColors.ink),
    ),
  );

  /// [text] with the highlighter under whatever a find turned up in [spans],
  /// moved from the block's own text to the text [text] lays out.
  Widget _marked(List<DocSpan> spans, Widget text) {
    final laidOut = <TextMark>[];
    for (final mark in marks) {
      if (mark.within.isNotEmpty) continue;
      final (start, end) = proseRangeOf(
        spans,
        mark.start,
        mark.end,
        foldBreaks: foldBreaks,
      );
      laidOut.add(
        TextMark(start: start, end: end, fill: mark.fill, color: mark.color),
      );
    }
    return ParagraphMarks(
      marks: laidOut,
      markerColor: AppColors.foundWash,
      child: text,
    );
  }

  Widget _paragraph(ParagraphBlock block) {
    // A caption belongs to the picture above it, so it is set as metadata
    // rather than as prose. The file's own style name is what says so.
    final caption = block.styleId == 'Caption';
    final text = _marked(
      block.spans,
      Text.rich(
        proseSpansOf(
          block.spans,
          color: caption ? AppColors.inkFaint : null,
          base: caption ? AppText.docMeta : null,
          foldBreaks: foldBreaks,
        ),
        textAlign: _align(block.align),
        style: (caption ? AppText.docMeta : AppText.pageBody).copyWith(
          color: caption ? AppColors.inkFaint : AppColors.inkSoft,
        ),
      ),
    );
    final quoted = block.quote ? QuoteBar(child: text) : text;
    if (block.indent <= 0) return quoted;
    return Padding(
      padding: EdgeInsets.only(left: kProseIndent * block.indent),
      child: quoted,
    );
  }

  Widget _listItem(ListItemBlock block) {
    final text = _marked(
      block.spans,
      Text.rich(
        proseSpansOf(block.spans, foldBreaks: foldBreaks),
        style: AppText.pageBody.copyWith(color: AppColors.inkSoft),
      ),
    );
    final checked = block.checked;
    final Widget marker;
    if (checked != null) {
      marker = Padding(
        padding: const EdgeInsets.only(top: kSpace4),
        child: CheckMark(checked: checked),
      );
    } else if (block.ordered) {
      marker = SizedBox(
        width: kProseMarkerGutter,
        child: Padding(
          padding: const EdgeInsets.only(top: kSpace4),
          child: Text(
            block.marker ?? '1.',
            textAlign: TextAlign.right,
            style: AppText.folio.copyWith(color: AppColors.inkFaint),
          ),
        ),
      );
    } else {
      marker = SizedBox(
        width: kProseMarkerGutter,
        child: Padding(
          padding: const EdgeInsets.only(top: kSpace8, right: kSpace4),
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              width: kProseBullet,
              height: kProseBullet,
              decoration: const BoxDecoration(
                color: AppColors.inkFaint,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: kProseIndent * block.level),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          marker,
          const SizedBox(width: kSpace8),
          Expanded(child: text),
        ],
      ),
    );
  }

  Widget _image(ImageBlock block) {
    final bytes = assets[block.assetKey];
    final width = block.width == null
        ? measure
        : (block.width! < measure ? block.width! : measure);
    final ratio = (block.width ?? 0) > 0 && (block.height ?? 0) > 0
        ? block.height! / block.width!
        : 0.0;
    final height = ratio > 0
        ? (width * ratio < kProseImageMaxHeight
              ? width * ratio
              : kProseImageMaxHeight)
        : kProseMissingImageHeight;
    if (bytes == null) {
      // The file names a picture it does not carry. The rect says so, the
      // same way an image this reader cannot decode does on a page.
      return Center(
        child: SizedBox(
          width: width,
          height: height,
          child: const UnsupportedImageBox(),
        ),
      );
    }
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kLeafRadius),
        child: Image.memory(
          bytes,
          width: width,
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  TextAlign? _align(DocAlign align) => switch (align) {
    DocAlign.center => TextAlign.center,
    DocAlign.end => TextAlign.right,
    DocAlign.justify => TextAlign.justify,
    DocAlign.start => null,
  };
}

/// A line break inside a paragraph, turned back into the space it stands for.
///
/// Markdown wraps its source at whatever column the writer liked, and every
/// one of those breaks is a space rather than a break. Word files are left
/// alone: a line break inside a Word paragraph was typed on purpose.
String foldLineBreak(String text) =>
    text.replaceAll(_lineBreak, ' ');

final RegExp _lineBreak = RegExp('[ \t]*\r?\n[ \t]*');

/// Where a run of a block's own text, [start] to [end], ends up in the text
/// [proseSpansOf] lays out for it.
///
/// The two differ in two ways. Inline code and raised or lowered letters are
/// set as pictures of themselves, each one character of the laid out text
/// however long it is, so a run inside one covers the whole picture. And a
/// Markdown paragraph's line breaks are folded into single spaces, which
/// shortens the text after each of them.
(int, int) proseRangeOf(
  List<DocSpan> spans,
  int start,
  int end, {
  bool foldBreaks = false,
}) {
  int laidOut(int offset, {required bool closing}) {
    var raw = 0;
    var laid = 0;
    for (final span in spans) {
      final length = span.text.length;
      final pictured = span.mono || span.script != 0;
      final inside = offset - raw;
      if (inside < length || (inside == length && !closing)) {
        if (inside <= 0) return laid;
        if (pictured) return closing ? laid + 1 : laid;
        if (!foldBreaks) return laid + inside;
        return laid + foldLineBreak(span.text.substring(0, inside)).length;
      }
      raw += length;
      laid += pictured
          ? 1
          : (foldBreaks ? foldLineBreak(span.text).length : length);
    }
    return laid;
  }

  final laidStart = laidOut(start, closing: false);
  final laidEnd = laidOut(end, closing: true);
  return (laidStart, laidEnd < laidStart ? laidStart : laidEnd);
}

/// The runs of a paragraph as one span tree.
InlineSpan proseSpansOf(
  List<DocSpan> spans, {
  TextStyle? base,
  Color? color,
  bool foldBreaks = false,
}) {
  return TextSpan(
    children: <InlineSpan>[
      for (final span in spans)
        if (span.mono)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MonoSpan(
              text: foldBreaks ? foldLineBreak(span.text) : span.text,
            ),
          )
        else if (span.script != 0)
          WidgetSpan(
            alignment: span.script > 0
                ? PlaceholderAlignment.top
                : PlaceholderAlignment.bottom,
            child: Text(
              foldBreaks ? foldLineBreak(span.text) : span.text,
              style: proseSpanStyle(
                span,
                base: base,
                color: color,
              ).copyWith(fontSize: (base ?? AppText.pageBody).fontSize! * 0.7),
            ),
          )
        else
          TextSpan(
            text: foldBreaks ? foldLineBreak(span.text) : span.text,
            style: proseSpanStyle(span, base: base, color: color),
          ),
    ],
  );
}

/// The reading column: one measure wide, whatever the sheet around it is.
///
/// 320 points at 15.5 point Inter is about fifty characters, which is the
/// measure a phone can hold without the eye losing the line on the way back.
class ProseColumn extends StatelessWidget {
  const ProseColumn({
    super.key,
    required this.blocks,
    this.assets = const <String, Uint8List>{},
    this.anchorBlock = 0,
    this.anchorKey,
    this.measure = kProseMeasure,
    this.foldBreaks = false,
    this.marksFor,
  });

  final List<DocBlock> blocks;
  final Map<String, Uint8List> assets;

  /// What a find has turned up in the block at a given place in [blocks].
  final List<BlockMark> Function(int block)? marksFor;

  /// The block the sheet opens at, and the key that finds it after layout.
  final int anchorBlock;
  final Key? anchorKey;

  final double measure;

  /// See [ProseBlockView.foldBreaks].
  final bool foldBreaks;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: measure,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) SizedBox(height: proseGap(blocks[i - 1], blocks[i])),
            KeyedSubtree(
              key: i == anchorBlock ? anchorKey : null,
              // Each block carries its own place in the column, so a match can
              // be found on the laid out page without a key for every block.
              child: MetaData(
                metaData: i,
                child: ProseBlockView(
                  block: blocks[i],
                  assets: assets,
                  measure: measure,
                  foldBreaks: foldBreaks,
                  marks: marksFor?.call(i) ?? const <BlockMark>[],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One renderer for both flowing formats.
///
/// Word files and Markdown both parse to the same sealed block model, so there
/// is one body rather than two: whatever a docx can say, a Markdown file says
/// through the same blocks, and any divergence between the two would be a
/// difference in the renderer rather than in the documents.
class ProseBody extends ReaderBody {
  const ProseBody({
    super.key,
    required this.store,
    required this.document,
    this.source,
    this.anchorBlock = 0,
    this.find,
  });

  final DocumentStore store;
  final QuireDocument document;

  /// The search open over this document, if there is one.
  final FindController? find;

  /// The file's own bytes as text, for the back of a Markdown sheet. A Word
  /// file has no source to show, so its back carries style names instead.
  final String? source;

  /// The block the sheet opens at.
  final int anchorBlock;

  List<DocBlock> get blocks => <DocBlock>[
    for (final section in document.sections) ...section.blocks,
  ];

  /// True when the parse produced a document with nothing in it, which a file
  /// that is empty or holds only whitespace does.
  bool get _empty => blocks.isEmpty;

  @override
  Widget buildFront(BuildContext context) {
    if (_empty) return _emptySheet();
    return ProseSheet(
      store: store,
      blocks: blocks,
      assets: document.assets,
      anchorBlock: anchorBlock,
      foldBreaks: document.sourceFormat == 'md',
      marksFor: _marksFor(),
      find: find,
    );
  }

  /// Turns a place in the laid out column back into the section and block a
  /// match names, and asks the search what it found there.
  List<BlockMark> Function(int block)? _marksFor() {
    final search = find;
    if (search == null) return null;
    final places = <(int, int)>[
      for (var s = 0; s < document.sections.length; s++)
        for (var b = 0; b < document.sections[s].blocks.length; b++) (s, b),
    ];
    return (block) {
      if (block < 0 || block >= places.length) return const <BlockMark>[];
      final (section, index) = places[block];
      return search.marksInBlock(section, index);
    };
  }

  /// The back of a flowing sheet: a Markdown file's own source, or the style
  /// names a Word file stored behind its paragraphs.
  ///
  /// Both are read straight off the parse the front is drawn from, so the back
  /// is ready in the same frame the front is and a fold never has to wait for
  /// it. The empty file is the only case with nothing to show, and it says so
  /// on both faces rather than turning over onto blank paper.
  @override
  Widget buildBack(BuildContext context) {
    if (_empty) return _emptySheet();
    final raw = source;
    if (raw != null && raw.trim().isNotEmpty) return SourceBack(source: raw);
    return ProseBack(blocks: blocks);
  }

  Widget _emptySheet() => TornPage(
    size: const Size(kSheetWidth, kSheetHeight),
    label: kDocumentEmptyLabel,
  );

  @override
  int get unitCount => blocks.length;

  /// A percentage, because a block index means nothing to a reader while a
  /// share of a flowing document means exactly what it says.
  @override
  String get positionLabel => store.positionLabel;

  /// A hairline per heading rather than per section.
  ///
  /// Both bundled prose files are one section, and a fore edge carrying a
  /// single mark is a map of nothing. A document's headings are its own
  /// divisions, and they are what a reader is scrubbing between.
  @override
  List<double> get foreEdgeMarks {
    final all = blocks;
    if (all.length <= 1) return const <double>[0];
    final marks = <double>[0];
    for (var i = 1; i < all.length; i++) {
      if (all[i] is HeadingBlock) marks.add(i / (all.length - 1));
    }
    return marks;
  }
}

/// The scrolling sheet a flowing document is read on.
///
/// The whole column is laid out at once rather than built lazily. The bundled
/// library's longest prose file is under sixty blocks, and having the real
/// height of every block is what lets the sheet open at a named block and lets
/// a scrub land somewhere rather than guess.
class ProseSheet extends StatefulWidget {
  const ProseSheet({
    super.key,
    required this.store,
    required this.blocks,
    this.assets = const <String, Uint8List>{},
    this.anchorBlock = 0,
    this.foldBreaks = false,
    this.marksFor,
    this.find,
  });

  final DocumentStore store;
  final List<DocBlock> blocks;
  final Map<String, Uint8List> assets;
  final int anchorBlock;

  /// See [ProseColumn.marksFor].
  final List<BlockMark> Function(int block)? marksFor;

  /// See [ProseBlockView.foldBreaks].
  final bool foldBreaks;

  /// The search open over the document, whose current match the sheet goes to
  /// each time it is sent there.
  final FindController? find;

  @override
  State<ProseSheet> createState() => _ProseSheetState();
}

class _ProseSheetState extends State<ProseSheet> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _anchor = GlobalKey();
  final GlobalKey _columnKey = GlobalKey();
  bool _anchored = false;

  /// How many times the sheet has gone to a match, so it goes once each time
  /// it is sent and not again every frame the find repaints.
  late int _revealed = widget.find?.reveals ?? 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  @override
  void didUpdateWidget(ProseSheet old) {
    super.didUpdateWidget(old);
    if (old.anchorBlock != widget.anchorBlock) _anchored = false;
    final reveals = widget.find?.reveals ?? _revealed;
    if (reveals != _revealed) {
      _revealed = reveals;
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToMatch());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
  }

  /// Glides the sheet until the current match rests on the reading line.
  ///
  /// The match is measured where the column actually set it, down to the line
  /// it starts on, rather than worked out from how far through the document
  /// its block is: blocks are all different heights, and a share of the
  /// document lands on the wrong one often enough to lose the word entirely.
  /// A second step while the sheet is still moving sets off again from
  /// wherever the sheet has got to, so the page never jumps back or ahead.
  void _goToMatch() {
    final finder = widget.find;
    if (!mounted || finder == null || !_controller.hasClients) return;
    if (finder.matches.isEmpty) return;
    final rect = _rectOf(finder.matches[finder.current]);
    if (rect == null) return;
    final position = _controller.position;
    final target = (position.pixels + rect.top - _readingLine()).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = target - position.pixels;
    if (distance.abs() < 1) return;
    _controller.animateTo(
      target,
      duration: findGlideFor(distance),
      curve: easeInOutCubic,
    );
  }

  /// Where on the sheet a match comes to rest: [kFindRevealLine] of the way
  /// down what is left of the screen under the find bar and above the foot.
  double _readingLine() {
    final safeArea = ReaderInsets.of(context);
    final top = safeArea.top + kHeadBandHeight;
    final bottom = _controller.position.viewportDimension -
        readerContentBottom(safeArea);
    return top + (bottom - top) * kFindRevealLine;
  }

  /// Where [match] is set, relative to the top of the sheet as it is scrolled
  /// now: the line the match starts on, or its whole block when the letters
  /// cannot be measured, as for a picture found by its description.
  Rect? _rectOf(FindMatch match) {
    final column = _columnKey.currentContext?.findRenderObject();
    final sheet = context.findRenderObject();
    if (column is! RenderBox || sheet is! RenderBox) return null;
    RenderBox? block;
    void visit(RenderObject object) {
      if (block != null) return;
      if (object is RenderMetaData && object.metaData == match.unit) {
        block = object;
        return;
      }
      if (object is RenderMetaData) return;
      object.visitChildren(visit);
    }

    column.visitChildren(visit);
    final found = block;
    if (found == null || match.unit >= widget.blocks.length) return null;
    final local = _lineIn(found, widget.blocks[match.unit], match) ??
        (Offset.zero & found.size);
    return MatrixUtils.transformRect(found.getTransformTo(sheet), local);
  }

  /// The line [match] starts on inside [box], the laid out [block], or null
  /// when the block sets no letters for it.
  Rect? _lineIn(RenderBox box, DocBlock block, FindMatch match) {
    final marked = <RenderParagraphMarks>[];
    void visit(RenderObject object) {
      if (object is RenderParagraphMarks) {
        marked.add(object);
        return;
      }
      object.visitChildren(visit);
    }

    box.visitChildren(visit);
    if (marked.isEmpty) return null;
    final RenderParagraphMarks paragraph;
    final int start;
    final int end;
    final path = match.path;
    switch (block) {
      case HeadingBlock(:final spans) ||
          ParagraphBlock(:final spans) ||
          ListItemBlock(:final spans) when path.length == 1:
        paragraph = marked.first;
        (start, end) = proseRangeOf(
          spans,
          match.start,
          match.end,
          foldBreaks: widget.foldBreaks,
        );
      case CodeBlock() when path.length == 1:
        paragraph = marked.first;
        (start, end) = (match.start, match.end);
      case TableBlock() when path.length == 4:
        final ordinal = ProseTable.cellOrdinal(block, path[1], path[2]);
        if (ordinal < 0 || ordinal >= marked.length) return null;
        paragraph = marked[ordinal];
        final cell = block.rows[path[1]].cells[path[2]];
        final before = ProseTable.lineStartOf(cell, path[3]);
        (start, end) = (before + match.start, before + match.end);
      default:
        return null;
    }
    final lines = paragraph.rectsOf(start, end);
    if (lines.isEmpty) return null;
    return MatrixUtils.transformRect(paragraph.getTransformTo(box), lines.first);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Where the reader is, as a share of the whole document.
  double get _fraction {
    if (!_controller.hasClients) return 0;
    final extent = _controller.position.maxScrollExtent;
    return extent <= 0 ? 0 : (_controller.offset / extent).clamp(0.0, 1.0);
  }

  int get _unit {
    final last = widget.blocks.length - 1;
    return last <= 0 ? 0 : (_fraction * last).round();
  }

  void _onScroll() {
    if (widget.store.position != _unit) widget.store.position = _unit;
  }

  void _afterFrame() {
    if (!mounted) return;
    if (!_anchored && widget.anchorBlock > 0) {
      _anchored = true;
      final context = _anchor.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: 0, duration: Duration.zero);
        // Leave the block's own space above it showing, so the first line
        // sits on paper rather than against the sheet's edge, and never more
        // than that, so the block before it does not bleed back in.
        if (_controller.hasClients) {
          _controller.jumpTo(
            (_controller.offset - _breathingRoom).clamp(
              0.0,
              _controller.position.maxScrollExtent,
            ),
          );
        }
      }
      return;
    }
    _follow();
  }

  /// How much paper to leave above the block the sheet opens at: the gap that
  /// block already carries, capped at the sheet's own margin.
  double get _breathingRoom {
    final at = widget.anchorBlock;
    if (at <= 0 || at >= widget.blocks.length) return kSheetPadding;
    final gap = proseGap(widget.blocks[at - 1], widget.blocks[at]);
    return gap < kSheetPadding ? gap : kSheetPadding;
  }

  /// Brings the sheet to where something other than this scroll put the
  /// reader: a scrub, a riffle, a search result.
  void _follow() {
    if (!_controller.hasClients) return;
    final wanted = widget.store.position;
    if (wanted == _unit) return;
    final last = widget.blocks.length - 1;
    if (last <= 0) return;
    _controller.jumpTo(
      (wanted / last) * _controller.position.maxScrollExtent,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The type is scaled rather than the page, because a document with no
    // pages of its own has nothing to magnify: what it has is a column of
    // words, and the right way to make those bigger is to set them bigger and
    // let the lines fall where they fall. A line you have to scroll sideways
    // to finish is not a line anybody reads twice.
    //
    // The reader's own size multiplies the phone's, rather than replacing it:
    // somebody who set their phone's text large should not have to set it
    // large again here.
    final system = SystemTextScale.of(context).scale(1);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(system * widget.store.textScale),
      ),
      child: _column(context),
    );
  }

  Widget _column(BuildContext context) {
    // The reader's word for where the phone's bars are, and not the phone's:
    // the sheet this column lies on has taken the phone's insets away.
    final safeArea = ReaderInsets.of(context);
    return SingleChildScrollView(
      controller: _controller,
      // Locked to where it is, the same as a page.
      physics: widget.store.lock.holdsPage
          ? const NeverScrollableScrollPhysics()
          : null,
      // The prose keeps its own breathing room and is held clear of the band
      // and the gesture bar on top of it, the same as a page is.
      padding: EdgeInsets.only(
        top: readerContentTop(safeArea) + kSheetPadding,
        bottom: readerContentBottom(safeArea) + kSheetPadding,
      ),
      child: Center(
        child: ProseColumn(
          key: _columnKey,
          blocks: widget.blocks,
          assets: widget.assets,
          anchorBlock: widget.anchorBlock,
          anchorKey: _anchor,
          foldBreaks: widget.foldBreaks,
          marksFor: widget.marksFor,
        ),
      ),
    );
  }
}
