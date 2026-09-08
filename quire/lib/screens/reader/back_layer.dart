import 'package:flutter/widgets.dart';

import '../../model/document.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';

/// What the back of a page says when there is nothing on it to read.
const kNoTextLayer = 'NO TEXT LAYER, SCANNED PAGE';

/// How wide the margin that carries a paragraph's style name is.
const kStyleMargin = 64.0;

/// The back of a sheet, which is the same surface every format lands on: one
/// column of [AppText.bodyTight] in [AppColors.inkSoft], padded like the
/// front.
///
/// The back exists to answer the one question no reader answers: why a search
/// missed a word that is plainly on the screen. That means it must show what
/// the app actually holds, never a prettier version of it.
class BackSurface extends StatelessWidget {
  const BackSurface({super.key, required this.child, this.controller});

  final Widget child;

  /// Supply one when the back has to scroll with something else.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.leafBack,
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(kSheetPadding),
        child: child,
      ),
    );
  }
}

/// A PDF page's extracted text layer, in reading order, at reading size.
///
/// The runs arrive already merged, so a line here is a line a person would
/// read, and it is exactly the string the search index holds.
class PdfTextBack extends StatelessWidget {
  const PdfTextBack({super.key, required this.lines});

  /// One merged run per line, in reading order.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const NoTextLayerBack();
    return BackSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: kSpace4),
              child: Text(
                line,
                style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }
}

/// The back of a page that is a picture.
///
/// It is stated in [AppColors.damage] because a page with no text layer is the
/// one case where a document cannot be searched, and a reader is owed that
/// fact rather than an empty column.
class NoTextLayerBack extends StatelessWidget {
  const NoTextLayerBack({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.leafBack,
      child: Center(
        child: Text(
          kNoTextLayer,
          textAlign: TextAlign.center,
          style: AppText.micro.copyWith(color: AppColors.damage),
        ),
      ),
    );
  }
}

/// The raw source behind a rendered Markdown sheet.
class SourceBack extends StatelessWidget {
  const SourceBack({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return BackSurface(
      child: Text(
        source,
        style: AppText.code.copyWith(color: AppColors.inkSoft),
      ),
    );
  }
}

/// The back of a styled document: the same paragraphs as plain text, with the
/// style each one came from named in the margin.
///
/// Word files carry their meaning in style names, and a document whose
/// headings are all `BodyText` with bigger type is a document that will not
/// outline, will not navigate and will not convert. The back is where that
/// shows.
class ProseBack extends StatelessWidget {
  const ProseBack({super.key, required this.blocks});

  final List<DocBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return BackSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final block in blocks)
            Padding(
              padding: const EdgeInsets.only(bottom: kSpace8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: kStyleMargin,
                    child: Text(
                      _styleOf(block),
                      style: AppText.micro.copyWith(color: AppColors.inkFaint),
                    ),
                  ),
                  const SizedBox(width: kSpace8),
                  Expanded(
                    child: Text(
                      _textOf(block),
                      style: AppText.bodyTight.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The style name the file itself carries, or the block's own kind when it
  /// has none. Uppercase is written out, never produced by a transform.
  String _styleOf(DocBlock block) => switch (block) {
    ParagraphBlock(:final styleId?) => styleId,
    ParagraphBlock(quote: true) => 'QUOTE',
    ParagraphBlock() => 'BODY',
    HeadingBlock(:final level) => 'H$level',
    ListItemBlock(ordered: true) => 'LIST N',
    ListItemBlock() => 'LIST',
    CodeBlock() => 'CODE',
    DividerBlock() => 'RULE',
    ImageBlock() => 'FIGURE',
    TableBlock() => 'TABLE',
  };

  String _textOf(DocBlock block) => switch (block) {
    ParagraphBlock(:final text) => text,
    HeadingBlock(:final text) => text,
    ListItemBlock(:final text) => text,
    CodeBlock(:final text) => text,
    DividerBlock() => '---',
    ImageBlock(:final alt, :final assetKey) => alt ?? assetKey,
    TableBlock(:final rows) => '${rows.length} rows',
  };
}

/// The back of a spreadsheet: what is stored, rather than what is shown.
///
/// A formatted cell hides two things, the value before formatting and the
/// formula that produced it, and both of them are what a person actually
/// needs when a number looks wrong.
class GridBack extends StatelessWidget {
  const GridBack({super.key, required this.table, this.rowLimit = 22});

  final TableBlock table;

  /// How many rows fit down the sheet before scrolling.
  final int rowLimit;

  @override
  Widget build(BuildContext context) {
    final columns = table.rows.isEmpty ? 1 : table.rows.first.cells.length;
    final widths = columnWidths(columns);
    return ColoredBox(
      color: AppColors.leafBack,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < table.rows.length && r < rowLimit; r++)
              SizedBox(
                height: kTableRowHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: kRowHeaderWidth,
                      child: Center(
                        child: Text(
                          '${r + 1}',
                          style: AppText.folioSmall.copyWith(
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: widths.open,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kCellPaddingX,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _raw(table.rows[r].cells.firstOrNull),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cell.copyWith(
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kCellPaddingX,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formula(table.rows[r].cells),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.code.copyWith(
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What the file stores, before any number format was applied to it.
  String _raw(DocCell? cell) {
    if (cell == null) return '';
    final raw = cell.raw;
    if (raw == null) return cell.text;
    return raw.toString();
  }

  /// The first formula on the row, which is the one that explains it.
  String _formula(List<DocCell> cells) {
    for (final cell in cells) {
      final formula = cell.formula;
      if (formula != null && formula.isNotEmpty) return '=$formula';
    }
    return '';
  }
}
