import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../../model/document.dart';
import '../../../services/document_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../back_layer.dart';
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
    decorationColor: span.href != null ? AppColors.rule : style.color,
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
        color: AppColors.panel,
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
        decoration: BoxDecoration(
          color: checked ? AppColors.thread : null,
          border: Border.all(
            color: checked ? AppColors.thread : AppColors.rule,
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
        ..color = AppColors.leaf
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
class QuoteBar extends StatelessWidget {
  const QuoteBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: kProseQuoteInset),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.rule, width: kProseQuoteBar),
        ),
      ),
      child: child,
    );
  }
}

/// A fenced block, on its own slab, scrolling sideways inside its own clip so
/// the reading column never scrolls with it.
class CodeSlab extends StatelessWidget {
  const CodeSlab({super.key, required this.block});

  final CodeBlock block;

  @override
  Widget build(BuildContext context) {
    final language = block.language;
    final named = language != null && language.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.panel,
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
              child: Text(
                block.text,
                style: AppText.code.copyWith(color: AppColors.inkSoft),
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
        child: const ColoredBox(color: AppColors.rule),
      ),
    );
  }
}

/// A table inside flowing prose: the file's own columns, fitted to the
/// reading measure and set a step smaller than the text around it, inside a
/// hairline box so it reads as an inset rather than as the column itself.
class ProseTable extends StatelessWidget {
  const ProseTable({super.key, required this.table, this.measure = kProseMeasure});

  final TableBlock table;
  final double measure;

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
        border: Border.all(color: AppColors.rule, width: 1),
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
            ? AppColors.panel
            : (index.isOdd ? AppColors.zebra : null),
        border: index == table.rows.length - 1
            ? null
            : Border(
                bottom: BorderSide(
                  color: row.header || leader
                      ? AppColors.rule
                      : AppColors.ruleFaint,
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
                child: _cell(row.cells[c], row.header, c),
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

  Widget _cell(DocCell cell, bool header, int index) {
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
        child: Text(
          cell.text,
          textAlign: align == DocAlign.center ? TextAlign.center : null,
          style: header
              ? AppText.cellHeader.copyWith(color: AppColors.ink)
              : AppText.cell.copyWith(color: AppColors.inkSoft),
        ),
      ),
    );
  }
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
  });

  final DocBlock block;

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
      CodeBlock() => CodeSlab(block: block as CodeBlock),
      DividerBlock() => ProseRule(measure: measure),
      ImageBlock() => _image(block as ImageBlock),
      TableBlock() => ProseTable(table: block as TableBlock, measure: measure),
    };
  }

  Widget _heading(HeadingBlock block) => Text.rich(
    proseSpansOf(
      block.spans,
      base: proseHeadingStyle(block),
      color: AppColors.ink,
      foldBreaks: foldBreaks,
    ),
    style: proseHeadingStyle(block).copyWith(color: AppColors.ink),
  );

  Widget _paragraph(ParagraphBlock block) {
    // A caption belongs to the picture above it, so it is set as metadata
    // rather than as prose. The file's own style name is what says so.
    final caption = block.styleId == 'Caption';
    final text = Text.rich(
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
    );
    final quoted = block.quote ? QuoteBar(child: text) : text;
    if (block.indent <= 0) return quoted;
    return Padding(
      padding: EdgeInsets.only(left: kProseIndent * block.indent),
      child: quoted,
    );
  }

  Widget _listItem(ListItemBlock block) {
    final text = Text.rich(
      proseSpansOf(block.spans, foldBreaks: foldBreaks),
      style: AppText.pageBody.copyWith(color: AppColors.inkSoft),
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
  });

  final List<DocBlock> blocks;
  final Map<String, Uint8List> assets;

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
              child: ProseBlockView(
                block: blocks[i],
                assets: assets,
                measure: measure,
                foldBreaks: foldBreaks,
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
  });

  final DocumentStore store;
  final QuireDocument document;

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
    );
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
  });

  final DocumentStore store;
  final List<DocBlock> blocks;
  final Map<String, Uint8List> assets;
  final int anchorBlock;

  /// See [ProseBlockView.foldBreaks].
  final bool foldBreaks;

  @override
  State<ProseSheet> createState() => _ProseSheetState();
}

class _ProseSheetState extends State<ProseSheet> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _anchor = GlobalKey();
  bool _anchored = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrame());
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
    return SingleChildScrollView(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: kSheetPadding),
      child: Center(
        child: ProseColumn(
          blocks: widget.blocks,
          assets: widget.assets,
          anchorBlock: widget.anchorBlock,
          anchorKey: _anchor,
          foldBreaks: widget.foldBreaks,
        ),
      ),
    );
  }
}
