import 'package:flutter/painting.dart';

/// The one family the interface is set in: a reader must not compete with
/// what it is displaying.
const kFontFamily = 'Inter';

/// The brand mark's face, and nothing else's. Only its semibold is bundled,
/// because [AppText.markName] is the one style that uses it.
///
/// The one relaxation of the single family rule. Document text, every label
/// and every other string in the app stay [kFontFamily].
const kMarkFamily = 'Quicksand';

/// Builds every style in the app, so no style can drift.
///
/// Colour is deliberately absent: it is applied at the call site, which is
/// what keeps one style usable in `ink` on a sheet and in `onAccent` on a
/// pill.
TextStyle _text({
  required double size,
  required double lineHeight,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
  bool tabular = false,
}) {
  return TextStyle(
    inherit: false,
    fontFamily: kFontFamily,
    fontSize: size,
    height: lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// Every text style in quire.
///
/// Tabular figures are not decoration. A column of numbers in proportional
/// digits ripples, and the ripple is what makes density feel sloppy. It is
/// also what makes the digit roll possible, because the box never resizes
/// mid roll.
abstract final class AppText {
  /// The word `quire` on the desk, and nowhere else.
  /// The brand mark's own face, and the only thing in the app set in anything
  /// but Inter.
  ///
  /// A reader should have no typographic voice of its own, because the
  /// document is the thing you are meant to hear. A name is the one exception:
  /// it is not the app talking about a document, it is the app saying which
  /// app it is, once, on a screen with nothing else on it.
  static final markName = TextStyle(
    inherit: false,
    fontFamily: kMarkFamily,
    fontSize: 34,
    height: 40 / 34,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    textBaseline: TextBaseline.alphabetic,
  );

  static final wordmark = _text(
    size: 30,
    lineHeight: 34,
    weight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// The collapsed wordmark in the desk bar.
  static final wordmarkSmall = _text(
    size: 17,
    lineHeight: 22,
    weight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// Empty state and failure headlines.
  static final display = _text(
    size: 26,
    lineHeight: 31,
    weight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// Card titles, sheet names, the signature screen title.
  static final title = _text(
    size: 17,
    lineHeight: 22,
    weight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// h1 inside a document.
  static final pageHeading1 = _text(
    size: 24,
    lineHeight: 30,
    weight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// h2 inside a document.
  static final pageHeading2 = _text(
    size: 19,
    lineHeight: 25,
    weight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// h3 inside a document.
  static final pageHeading3 = _text(
    size: 16,
    lineHeight: 21,
    weight: FontWeight.w600,
  );

  /// Document body text, every format.
  static final pageBody = _text(size: 15.5, lineHeight: 24);

  /// A bold run inside body text. 600, never 700, because 700 shouts in a
  /// reading column.
  static final pageBodyBold = _text(
    size: 15.5,
    lineHeight: 24,
    weight: FontWeight.w600,
  );

  /// An italic run. There is no italic face in the bundle and none is added,
  /// and it is never faked with a skew. Colour it `inkSoft` at the call site.
  static final pageBodyItalic = _text(
    size: 15.5,
    lineHeight: 24,
    weight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// Interface paragraphs, the whole back layer, search snippets.
  static final bodyTight = _text(size: 14, lineHeight: 19);

  /// A list row's document title.
  ///
  /// One step down from [title] and set in the regular weight, because six
  /// titles in a column set in semibold read as six headings rather than as a
  /// list of six documents.
  static final rowTitle = _text(size: 16, lineHeight: 20);

  /// The search pill's placeholder and whatever is typed into it.
  static final search = _text(size: 15, lineHeight: 20);

  /// A drawer row's label, and the same label on the row you are standing on.
  static final drawerRow = _text(size: 16, lineHeight: 21);
  static final drawerRowSelected = _text(
    size: 16,
    lineHeight: 21,
    weight: FontWeight.w500,
  );

  /// The current sort, on the left of the sort row.
  static final sortLabel = _text(
    size: 14,
    lineHeight: 19,
    weight: FontWeight.w500,
  );

  /// A sort menu row, and the one row in each group that carries a check.
  static final menuRow = _text(size: 15, lineHeight: 20);
  static final menuRowSelected = _text(
    size: 15,
    lineHeight: 20,
    weight: FontWeight.w500,
  );

  /// The single letter in the top bar's avatar.
  static final avatar = _text(
    size: 15,
    lineHeight: 20,
    weight: FontWeight.w600,
  );

  /// A drawer destination's headline, and the sentence under it.
  static final destinationTitle = _text(
    size: 19,
    lineHeight: 25,
    weight: FontWeight.w600,
  );
  static final destinationBody = _text(size: 14, lineHeight: 20);

  /// An action pill's label on the expanding button.
  ///
  /// [label] one size up: the pill is a control like every other, so it keeps
  /// the control face and the control's own tightening rather than becoming a
  /// second recipe at a second size.
  static final actionPill = _text(
    size: 15,
    lineHeight: 20,
    weight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  /// A card's meta line.
  static final docMeta = _text(size: 13, lineHeight: 17);

  /// Controls, buttons, sheet tabs, the cell bar's value.
  static final label = _text(
    size: 13,
    lineHeight: 16,
    weight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  /// Status lines and placeholders.
  static final hint = _text(
    size: 13,
    lineHeight: 17,
    weight: FontWeight.w500,
  );

  /// Code blocks, code spans, the Markdown back layer, a formula. Inter with
  /// tabular figures on a `surfaceHigh` slab, which is honest and costs
  /// nothing.
  static final code = _text(
    size: 13.5,
    lineHeight: 20,
    weight: FontWeight.w500,
    letterSpacing: 0.1,
    tabular: true,
  );

  /// Every spreadsheet and CSV cell.
  static final cell = _text(size: 13, lineHeight: 17, tabular: true);

  /// A column's header label.
  static final cellHeader = _text(
    size: 12,
    lineHeight: 15,
    weight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  /// Page numbers, match counts, cell references, the folio chip.
  static final folio = _text(
    size: 12,
    lineHeight: 15,
    weight: FontWeight.w500,
    letterSpacing: 1.2,
    tabular: true,
  );

  /// Thumbnail folios, spreadsheet row numbers.
  static final folioSmall = _text(
    size: 10,
    lineHeight: 13,
    weight: FontWeight.w500,
    letterSpacing: 1.0,
    tabular: true,
  );

  /// Shelf chips, dock labels, the `SIGNED` chip.
  static final chipLabel = _text(
    size: 11,
    lineHeight: 14,
    weight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// A type mark's letters, on a 30 mark. The mark scales this style with
  /// itself, so the letters on a 20 mark are this face at two thirds of this
  /// size rather than a second, smaller style.
  static final typeMark = _text(
    size: 10,
    lineHeight: 12,
    weight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  /// Standing heads, column letters, colophons.
  static final micro = _text(
    size: 9,
    lineHeight: 11,
    weight: FontWeight.w600,
    letterSpacing: 0.8,
  );
}
