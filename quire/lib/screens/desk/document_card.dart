import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/marked_text.dart';
import '../../widgets/press_fade.dart';
import '../../widgets/type_mark.dart';
import 'document_row.dart';
import 'thumbnail.dart';

/// The hue a format wears, and the only place in the app a format colour is
/// chosen. Five hues with one home, so a colour can never be mistaken for the
/// two accents that mean found and you.
Color chromaFor(DocFormat format) => switch (format) {
      DocFormat.pdf => AppColors.fmtPdf,
      DocFormat.docx => AppColors.fmtDocx,
      DocFormat.xlsx => AppColors.fmtXlsx,
      DocFormat.csv => AppColors.fmtCsv,
      DocFormat.md => AppColors.fmtMd,
    };

/// [value] with a comma every three digits.
///
/// Every count on the desk goes through this, because an ungrouped five digit
/// number is a number you have to count the digits of before you know it.
String groupedNumber(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// What a card counts, with its noun written out in both cases.
///
/// Both cases are literals rather than one string put through a transform, so
/// a golden reads exactly what the source says.
typedef CardUnits = ({int count, String upper, String lower});

/// The count a document prints beside its format: pages for a page file, rows
/// for a grid, words for prose, because those are the three things a reader
/// actually weighs a document by.
///
/// Null means nothing has parsed the file yet, and the line then makes no
/// claim at all rather than printing a zero it would have to take back.
CardUnits? cardUnits(LibraryEntry entry, DocumentStore? store) {
  if (store == null) return null;
  switch (entry.format) {
    case DocFormat.pdf:
      final count = store.pdfPageCount;
      if (count <= 0) return null;
      return count == 1
          ? (count: count, upper: 'PAGE', lower: 'page')
          : (count: count, upper: 'PAGES', lower: 'pages');
    case DocFormat.xlsx:
    case DocFormat.csv:
      final count = store.unitCount;
      if (count <= 0) return null;
      return count == 1
          ? (count: count, upper: 'ROW', lower: 'row')
          : (count: count, upper: 'ROWS', lower: 'rows');
    case DocFormat.docx:
    case DocFormat.md:
      final count = store.wordCount;
      if (count <= 0) return null;
      return count == 1
          ? (count: count, upper: 'WORD', lower: 'word')
          : (count: count, upper: 'WORDS', lower: 'words');
  }
}

/// A peelable card's meta line, as in `PDF · 6 PAGES · 306 KB`.
String cardMeta(LibraryEntry entry, DocumentStore? store) {
  final units = cardUnits(entry, store);
  final parts = <String>[
    entry.mark,
    if (units != null) '${groupedNumber(units.count)} ${units.upper}',
    entry.sizeLabel,
  ];
  return parts.join(' · ');
}

/// What a peelable card holds on its back: the file's true detail, in the
/// plain terms the front rounds off.
List<String> cardBackLines(LibraryEntry entry, DocumentStore? store) {
  final units = cardUnits(entry, store);
  return <String>[
    entry.fileName,
    '${groupedNumber(entry.bytes)} bytes',
    if (units != null) '${groupedNumber(units.count)} ${units.lower}',
    if (store != null && store.signed) 'signed',
    if (store == null || !store.opened)
      'never opened'
    else if (store.positionLabel.isEmpty)
      'opened'
    else
      'left at ${store.positionLabel}',
  ];
}

/// One document in the grid: a header naming it, and under that the document's
/// own first page.
///
/// The page is the point. A card whose picture were a coloured glyph would be
/// a list row laid out in two columns, and the grid would be costing twice the
/// height of a list for less information. What a grid buys is that a document
/// is recognised by its shape before its name is read, and only a real page
/// can be recognised.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.entry,
    required this.store,
    this.query = '',
    this.onOpen,
    this.onOverflow,
  });

  final LibraryEntry entry;

  /// What is known about the file, or null before anything has read it.
  final DocumentStore? store;

  /// The search, marked wherever it appears in the title.
  final String query;

  final VoidCallback? onOpen;

  /// The three dots. The menu behind them belongs to the shell.
  final void Function(Rect target)? onOverflow;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onOpen,
      semanticLabel: entry.title,
      washRadius: kGridCardRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(kGridCardRadius),
          border: AppEdges.all(context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kGridCardHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: kGridCardPadding,
                ),
                child: Row(
                  children: [
                    TypeMark(
                      letters: entry.mark,
                      chroma: chromaFor(entry.format),
                      size: kTypeMarkGridSize,
                    ),
                    const SizedBox(width: kGridHeaderGap),
                    Expanded(
                      child: MarkedText(
                        entry.title,
                        style: AppText.label.copyWith(color: AppColors.ink),
                        markerColor: AppColors.foundWash,
                        query: query,
                        maxLines: 2,
                        ellipsis: '…',
                      ),
                    ),
                    OverflowTarget(
                      size: kGridOverflowTarget,
                      onTap: onOverflow,
                    ),
                  ],
                ),
              ),
            ),
            Thumbnail(store: store),
          ],
        ),
      ),
    );
  }
}
