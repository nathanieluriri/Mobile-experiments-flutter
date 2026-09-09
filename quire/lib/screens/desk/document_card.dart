import 'package:flutter/widgets.dart';

import '../../data/library.dart';
import '../../painting/fold_painter.dart';
import '../../services/document_store.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/digit_roll.dart';
import '../../widgets/marked_text.dart';
import '../../widgets/paper_sheet.dart';
import '../../widgets/type_mark.dart';

/// How wide a title may set before it gives up and ellipsises.
const kCardTitleWidth = 246.0;

/// Where the meta line, the progress track and the position sit in the card.
const kCardMetaTop = 46.0;
const kCardProgressTop = 70.0;
const kCardPositionLeft = 186.0;
const kCardPositionTop = 66.0;

/// How tall the `SIGNED` chip stands, and how much room its label gets either
/// side.
const kSignedChipHeight = 20.0;
const kSignedChipPaddingX = 8.0;

/// Where the back layer's lines start, and how far apart they sit.
const kCardBackInset = 14.0;
const kCardBackTop = 18.0;
const kCardBackLineHeight = 19.0;

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

/// The count a card prints beside the format: pages for a page file, rows for
/// a grid, words for prose, because those are the three things a reader
/// actually weighs a document by.
///
/// Null means nothing has parsed the file yet, and the card then makes no
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

/// The card's meta line, as in `PDF · 6 PAGES · 306 KB`.
String cardMeta(LibraryEntry entry, DocumentStore? store) {
  final units = cardUnits(entry, store);
  final parts = <String>[
    entry.mark,
    if (units != null) '${groupedNumber(units.count)} ${units.upper}',
    entry.sizeLabel,
  ];
  return parts.join(' · ');
}

/// What the card holds on its back: the file's true detail, in the plain terms
/// the front rounds off.
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

/// One document on the desk: 362 x 96 of paper carrying a type mark, a title,
/// a meta line, and whatever of your own progress there is to show.
///
/// It draws no fold of its own. The peel around it owns the corner, because a
/// corner at rest and a corner under a finger have to be the same corner.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.entry,
    required this.store,
    this.query = '',
  });

  final LibraryEntry entry;

  /// What is known about the file, or null before anything has read it.
  final DocumentStore? store;

  /// The desk search, marked wherever it appears in the title.
  final String query;

  @override
  Widget build(BuildContext context) {
    final held = store;
    final opened = held != null && held.opened;
    final label = held?.positionLabel ?? '';
    return PaperSheet(
      width: kCardWidth,
      height: kCardHeight,
      child: Stack(
        children: [
          Positioned(
            left: kCardPadding,
            top: (kCardHeight - kTypeMarkHeight) / 2,
            child: TypeMark(
              letters: entry.mark,
              chroma: chromaFor(entry.format),
            ),
          ),
          Positioned(
            left: kCardTextLeft,
            top: kSpace20,
            width: kCardTitleWidth,
            child: MarkedText(
              entry.title,
              style: AppText.title.copyWith(color: AppColors.ink),
              markerColor: AppColors.markerWash,
              query: query,
              maxLines: 1,
              ellipsis: '…',
            ),
          ),
          Positioned(
            left: kCardTextLeft,
            top: kCardMetaTop,
            child: Text(
              cardMeta(entry, held),
              style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
            ),
          ),
          if (opened) ...<Widget>[
            Positioned(
              left: kCardTextLeft,
              top: kCardProgressTop,
              child: _Progress(fraction: held.progress),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: kCardPositionLeft,
                top: kCardPositionTop,
                child: DigitRoll(
                  label,
                  style: AppText.folio,
                  color: AppColors.inkFaint,
                ),
              ),
          ],
          if (held != null && held.signed)
            const Positioned(
              right: kCardPadding,
              top: kSpace20,
              child: _SignedChip(),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kCardProgressWidth,
      height: kCardProgressHeight,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.rule)),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: kCardProgressWidth * fraction.clamp(0, 1),
            child: const ColoredBox(color: AppColors.thread),
          ),
        ],
      ),
    );
  }
}

class _SignedChip extends StatelessWidget {
  const _SignedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kSignedChipHeight,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: kSignedChipPaddingX),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(kChipRadius),
      ),
      child: Text(
        'SIGNED',
        style: AppText.chipLabel.copyWith(color: AppColors.inkFaint),
      ),
    );
  }
}

/// The back of a card, painted into whatever the peel has torn away.
///
/// It is a painter rather than a widget because the torn region is a polygon
/// the fold recomputes every frame, and clipping a laid out subtree to a
/// moving polygon costs a save layer a frame for a result that is four lines
/// of text.
///
/// The lines set to the right edge because a fold can reveal at most the half
/// of the sheet its own corner is in, and this sheet's corner is the bottom
/// right one. Setting them left would put the detail in the half no peel of
/// this card ever uncovers.
class CardBackPainter extends CustomPainter {
  const CardBackPainter({required this.lines});

  final List<String> lines;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.leafBack);
    final style = AppText.bodyTight.copyWith(color: AppColors.inkSoft);
    final measure = size.width - kCardBackInset * 2;
    var y = kCardBackTop;
    for (final line in lines) {
      final painter = TextPainter(
        text: TextSpan(text: line, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: measure);
      painter.paint(
        canvas,
        Offset(size.width - kCardBackInset - painter.width, y),
      );
      painter.dispose();
      y += kCardBackLineHeight;
    }
  }

  @override
  bool shouldRepaint(CardBackPainter old) => !_same(old.lines, lines);

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The card's own front, redrawn so the fold can show it through the back of
/// the flap.
///
/// Only the marks are drawn and never a ground, because paper shows its ink
/// through, not its whiteness.
class CardFacePainter extends CustomPainter {
  const CardFacePainter({
    required this.title,
    required this.meta,
    required this.letters,
    required this.chroma,
  });

  final String title;
  final String meta;
  final String letters;
  final Color chroma;

  @override
  void paint(Canvas canvas, Size size) {
    const markSize = Size(kTypeMarkWidth, kTypeMarkHeight);
    canvas.save();
    canvas.translate(kCardPadding, (kCardHeight - kTypeMarkHeight) / 2);
    canvas.drawRect(Offset.zero & markSize, Paint()..color = AppColors.leaf);
    FoldPainter.atRest(
      restInset: kTypeMarkFoldInset,
      background: AppColors.leaf,
      flapColor: chroma,
    ).paint(canvas, markSize);
    canvas.drawRect(
      (Offset.zero & markSize).deflate(0.5),
      Paint()
        ..color = AppColors.rule
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _line(
      canvas,
      letters,
      AppText.micro.copyWith(color: chroma),
      const Offset(0, kTypeMarkHeight - kTypeMarkFoldInset - 11),
      markSize.width,
      centre: true,
    );
    canvas.restore();

    _line(
      canvas,
      title,
      AppText.title.copyWith(color: AppColors.ink),
      const Offset(kCardTextLeft, kSpace20),
      kCardTitleWidth,
    );
    _line(
      canvas,
      meta,
      AppText.docMeta.copyWith(color: AppColors.inkFaint),
      const Offset(kCardTextLeft, kCardMetaTop),
      kCardTitleWidth,
    );
  }

  void _line(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset at,
    double width, {
    bool centre = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: centre ? TextAlign.center : TextAlign.start,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: centre ? width : 0, maxWidth: width);
    painter.paint(canvas, at);
    painter.dispose();
  }

  @override
  bool shouldRepaint(CardFacePainter old) =>
      old.title != title ||
      old.meta != meta ||
      old.letters != letters ||
      old.chroma != chroma;
}
