import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../model/document.dart';
import '../pdf/display_list.dart';
import '../screens/reader/bodies/prose_body.dart';
import '../screens/reader/bodies/spine_table.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';
import 'pdf_page_painter.dart';
import 'spine_glyph_painter.dart';

/// How tall a page is recorded, in points.
///
/// A thumbnail is the card's full width and [kThumbnailAspect] of that in
/// height, so a page recorded this tall against the reading sheet's own width
/// fills the rect exactly: nothing is recorded that no card will ever draw.
const double kThumbnailPageHeight = kSheetWidth / kThumbnailAspect;

/// Every rule a thumbnail draws, in page points, scaled down with the rest of
/// the page. Wider than this and a table reads as a grid of bars rather than
/// as a table.
const double kThumbnailRule = 1.0;

/// The narrowest a folded column can be and still be worth a label.
const double kThumbnailLabelMin = 24.0;

/// One document's first screen, recorded once.
///
/// A grid of six cards then draws six finished pictures every frame instead of
/// interpreting six content streams, which is the difference between a grid
/// that scrolls and a grid that stutters. It is recorded at the page's own
/// size and scaled by whoever draws it, so one recording serves any card.
@immutable
class ThumbnailPicture {
  const ThumbnailPicture(this.picture, this.source);

  final ui.Picture picture;

  /// The page the picture was recorded at, in its own points.
  final Size source;
}

/// The first page of a PDF, drawn by the same painter the reader draws it
/// with, so a card shows the page rather than an impression of it.
///
/// Images are left out. Decoding one is asynchronous and recording is not, and
/// a thumbnail that waited on a decode would put an empty card on screen,
/// which is the one thing a grid must never do.
ThumbnailPicture recordPdfThumbnail(PageDisplayList list) {
  final source = Size(list.widthPts, list.heightPts);
  return _record(source, (canvas) {
    PageListPainter(
      list: list,
      runs: mergeRuns(list.texts),
      images: const <String, ui.Image>{},
      serifFamily: kFontFamily,
      sansFamily: kFontFamily,
    ).paint(canvas, source);
  });
}

/// The first screen of a flowing document, spaced the way its own sheet spaces
/// it and set in ink that reads on paper.
ThumbnailPicture recordProseThumbnail(
  List<DocBlock> blocks, {
  bool foldBreaks = false,
}) {
  const source = Size(kSheetWidth, kThumbnailPageHeight);
  return _record(source, (canvas) {
    var y = kSheetPadding;
    for (var i = 0; i < blocks.length && y < source.height; i++) {
      if (i > 0) y += proseGap(blocks[i - 1], blocks[i]);
      y += _proseBlock(canvas, blocks[i], y, foldBreaks: foldBreaks);
    }
  });
}

/// The first screen of a spreadsheet or a CSV, laid out the way the sheet body
/// lays it out: a row header gutter, a band of labels, one open column
/// carrying its values, and the rest of the file folded into spines.
ThumbnailPicture recordGridThumbnail(TableBlock table) {
  const source = Size(kSheetWidth, kThumbnailPageHeight);
  return _record(source, (canvas) => _grid(canvas, table, source));
}

/// A page with nothing on it, for a document nothing has been able to read.
///
/// It is not a placeholder standing in for a page that exists. It is what this
/// app knows about a file it could not open, which is nothing.
ThumbnailPicture recordEmptyThumbnail() =>
    _record(const Size(kSheetWidth, kThumbnailPageHeight), (_) {});

ThumbnailPicture _record(Size source, void Function(Canvas canvas) draw) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & source);
  draw(canvas);
  return ThumbnailPicture(recorder.endRecording(), source);
}

/// The card's white rect, carrying the document's own first page.
///
/// The picture is scaled to the card's width and clipped to its height, so a
/// tall page shows its top rather than being squashed into a square. A page is
/// recognised by the shape of its first screen, and squashing it is exactly
/// what destroys that shape.
class ThumbnailPainter extends CustomPainter {
  const ThumbnailPainter(this.thumbnail);

  /// The recorded page, or null while a document has not been read at all.
  final ThumbnailPicture? thumbnail;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.page);
    final held = thumbnail;
    if (held == null || held.source.width <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / held.source.width);
    canvas.drawPicture(held.picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ThumbnailPainter old) => old.thumbnail != thumbnail;
}

/// Draws one block with its top at [top], and returns how tall it turned out.
///
/// The gaps between blocks come from [proseGap] itself rather than from a copy
/// of its numbers, because a thumbnail whose blocks sat differently from the
/// sheet's would be a picture of a document this app does not render.
double _proseBlock(
  Canvas canvas,
  DocBlock block,
  double top, {
  required bool foldBreaks,
}) {
  switch (block) {
    case HeadingBlock():
      return _line(
        canvas,
        _plain(block.text, foldBreaks),
        proseHeadingStyle(block).copyWith(color: AppColors.pageInk),
        Offset(kSheetPadding, top),
        kProseMeasure,
      );
    case ParagraphBlock():
      final indent = kProseIndent * block.indent +
          (block.quote ? kProseQuoteInset : 0);
      final height = _line(
        canvas,
        _plain(block.text, foldBreaks),
        AppText.pageBody.copyWith(color: AppColors.pageInkSoft),
        Offset(kSheetPadding + indent, top),
        kProseMeasure - indent,
      );
      if (block.quote) {
        canvas.drawRect(
          Rect.fromLTWH(kSheetPadding, top, kProseQuoteBar, height),
          _ink,
        );
      }
      return height;
    case ListItemBlock():
      final indent = kProseIndent * block.level;
      final left = kSheetPadding + indent;
      if (block.ordered) {
        _line(
          canvas,
          block.marker ?? '1.',
          AppText.folio.copyWith(color: AppColors.pageInkSoft),
          Offset(left, top + kSpace4),
          kProseMarkerGutter,
          align: TextAlign.right,
        );
      } else {
        canvas.drawCircle(
          Offset(
            left + kProseMarkerGutter - kSpace4 - kProseBullet / 2,
            top + kSpace8 + kProseBullet / 2,
          ),
          kProseBullet / 2,
          _ink,
        );
      }
      final textLeft = left + kProseMarkerGutter + kSpace8;
      return _line(
        canvas,
        _plain(block.text, foldBreaks),
        AppText.pageBody.copyWith(color: AppColors.pageInkSoft),
        Offset(textLeft, top),
        kSheetPadding + kProseMeasure - textLeft,
      );
    case CodeBlock():
      final height = _line(
        canvas,
        block.text,
        AppText.code.copyWith(color: AppColors.pageInkSoft),
        Offset(kSheetPadding + kSpace12, top + kSpace12),
        kProseMeasure - kSpace12 * 2,
      );
      final slab = Rect.fromLTWH(
        kSheetPadding,
        top,
        kProseMeasure,
        height + kSpace12 * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(slab, const Radius.circular(kCodeRadius)),
        _stroke,
      );
      return slab.height;
    case DividerBlock():
      final width = kProseMeasure * kProseRuleFraction;
      canvas.drawRect(
        Rect.fromLTWH(
          kSheetPadding + (kProseMeasure - width) / 2,
          top,
          width,
          kThumbnailRule,
        ),
        _ink,
      );
      return kThumbnailRule;
    case ImageBlock():
      // The document's own media is not decoded for a thumbnail, so the
      // picture keeps the room it occupies on the page and says so with the
      // same rect the reader draws round a picture it cannot show.
      final height = block.height ?? kProseMissingImageHeight;
      final box = Rect.fromLTWH(
        kSheetPadding,
        top,
        kProseMeasure,
        height < kProseImageMaxHeight ? height : kProseImageMaxHeight,
      );
      canvas.drawRect(box, _stroke);
      return box.height;
    case TableBlock():
      return _proseTable(canvas, block, top);
  }
}

/// A table inside prose: the file's own rows, at the sheet's own row heights.
double _proseTable(Canvas canvas, TableBlock table, double top) {
  final columns = _columnsOf(table);
  if (columns == 0) return 0;
  final width = kProseMeasure * kProseTableScale;
  final cell = width / columns;
  var y = top;
  for (var r = 0; r < table.rows.length; r++) {
    final row = table.rows[r];
    final height = (row.header ? kTableHeaderHeight : kTableRowHeight) *
        kProseTableScale;
    for (var c = 0; c < columns; c++) {
      final held = cellAt(table, r, c);
      if (held == null || held.merged) continue;
      _line(
        canvas,
        flattenCell(held.text),
        (row.header ? AppText.cellHeader : AppText.cell).copyWith(
          color: row.header ? AppColors.pageInk : AppColors.pageInkSoft,
        ),
        Offset(kSheetPadding + c * cell + kCellPaddingX, y + kSpace4),
        cell - kCellPaddingX * 2,
        maxLines: 1,
      );
    }
    y += height;
    canvas.drawRect(
      Rect.fromLTWH(kSheetPadding, y, width, kThumbnailRule),
      _ink,
    );
  }
  return y - top;
}

/// The spreadsheet, as the sheet body lays it out.
void _grid(Canvas canvas, TableBlock table, Size source) {
  final columns = _columnsOf(table);
  if (columns == 0) return;
  final headerRows = table.frozenRows > 0
      ? table.frozenRows
      : (table.rows.isNotEmpty && table.rows.first.header ? 1 : 0);
  final labelRow = headerRows == 0 ? null : headerRows - 1;
  final widths = spineWidths(columns, open: 0);

  // The band of labels, and the one rule in the whole grid drawn at full
  // strength, because it is the line that separates what the columns are
  // called from what they hold.
  var x = kRowHeaderWidth;
  for (var c = 0; c < columns; c++) {
    if (widths[c] >= kThumbnailLabelMin) {
      final label = labelRow == null
          ? columnLetter(c)
          : flattenCell(cellAt(table, labelRow, c)?.text ?? columnLetter(c));
      _line(
        canvas,
        label,
        AppText.cellHeader.copyWith(color: AppColors.pageInk),
        Offset(x + kCellPaddingX, kSpace12),
        widths[c] - kCellPaddingX * 2,
        maxLines: 1,
      );
    }
    x += widths[c];
  }
  canvas.drawRect(
    Rect.fromLTWH(0, kTableHeaderHeight, source.width, kThumbnailRule),
    Paint()..color = AppColors.pageInk,
  );

  final spines = <int, List<SpineValue>>{
    for (var c = 1; c < columns; c++)
      c: spineValuesFor(table, c, from: headerRows),
  };
  var y = kTableHeaderHeight + kThumbnailRule;
  for (var r = headerRows; r < table.rows.length && y < source.height; r++) {
    _line(
      canvas,
      '${r - headerRows + 1}',
      AppText.folioSmall.copyWith(color: AppColors.pageInkSoft),
      Offset(0, y + kSpace8),
      kRowHeaderWidth - kCellPaddingX,
      align: TextAlign.right,
    );
    x = kRowHeaderWidth;
    for (var c = 0; c < columns; c++) {
      if (c == 0) {
        _line(
          canvas,
          flattenCell(cellAt(table, r, c)?.text ?? ''),
          AppText.cell.copyWith(color: AppColors.pageInkSoft),
          Offset(x + kCellPaddingX, y + kSpace8),
          widths[c] - kCellPaddingX * 2,
          maxLines: 1,
        );
      } else {
        _spine(canvas, spines[c]![r - headerRows], x, y, widths[c]);
      }
      x += widths[c];
    }
    y += kTableRowHeight;
    canvas.drawRect(
      Rect.fromLTWH(0, y, source.width, kThumbnailRule),
      _ink,
    );
  }
  canvas.drawRect(
    Rect.fromLTWH(kRowHeaderWidth, 0, kThumbnailRule, source.height),
    _ink,
  );
}

/// One folded cell: the same bar or dot the sheet body folds it to.
void _spine(Canvas canvas, SpineValue value, double x, double y, double width) {
  final middle = y + kTableRowHeight / 2;
  switch (value.mark) {
    case SpineMark.none:
      return;
    case SpineMark.bar:
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          middle - kSpineBarHeight / 2,
          spineBarWidth(value.extent).clamp(0, width),
          kSpineBarHeight,
        ),
        _ink,
      );
    case SpineMark.dot:
      canvas.drawCircle(Offset(x + width / 2, middle), kSpineDot / 2, _ink);
  }
}

/// How many columns [table] has, counting a ragged row that runs past its
/// header.
int _columnsOf(TableBlock table) {
  var columns = table.columns.length;
  for (final row in table.rows) {
    if (row.cells.length > columns) columns = row.cells.length;
  }
  return columns;
}

/// Sets [text] at [at] inside [width] and returns the height it took.
double _line(
  Canvas canvas,
  String text,
  TextStyle style,
  Offset at,
  double width, {
  int maxLines = 0,
  TextAlign align = TextAlign.left,
}) {
  if (width <= 0) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: maxLines == 0 ? null : maxLines,
    ellipsis: maxLines == 0 ? null : '…',
  )..layout(minWidth: width, maxWidth: width);
  painter.paint(canvas, at);
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Markdown wraps its source wherever the writer liked, and every one of those
/// breaks is a space. A Word file's breaks were typed on purpose.
String _plain(String text, bool foldBreaks) =>
    foldBreaks ? foldLineBreak(text) : text;

/// Every rule, gridline, bullet and spine mark on a thumbnail.
Paint get _ink => Paint()..color = AppColors.pageInkSoft;

/// The outline round a slab or a picture a thumbnail does not fill.
Paint get _stroke => Paint()
  ..color = AppColors.pageInkSoft
  ..style = PaintingStyle.stroke
  ..strokeWidth = kThumbnailRule;
