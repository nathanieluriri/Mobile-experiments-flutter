import 'dart:ui';

/// The whole palette. One theme, dark, no toggle. Every value is opaque unless
/// an alpha is written into the hex.
///
/// Three families and one rule each. The greys carry structure, so nothing in
/// the app needs a shadow to sit above anything else: a surface is told from
/// the ground by its own value and, where that is not enough, by [hairline].
/// The purples carry the app itself, and they appear on exactly three things:
/// the action button, the current selection, and whatever is happening right
/// now. The formats carry identity, one hue each, on a type mark and a fore
/// edge tick and nowhere else.
///
/// That division is what lets a hundred marks on a page read as density
/// instead of confetti: a purple pixel is always the app, a yellow pixel is
/// always a match, and a red pixel is always damage.
abstract final class AppColors {
  // Grounds.

  /// The app background, behind everything.
  static const ground = Color(0xFF131316);

  /// A raised surface: a grid card, the drawer, the sort menu, a sheet at
  /// rest, the reading sheet itself.
  static const surface = Color(0xFF1E1E22);

  /// A control on a surface: the search pill, an unselected toggle, an
  /// overflow target, a header rail, a code slab.
  static const surfaceHigh = Color(0xFF2B2930);

  /// Every rule, border and divider in the app, one physical pixel wide.
  static const hairline = Color(0xFF2F2F35);

  /// [hairline] at 0.55, for the gridlines between two leader rules. Not a
  /// second rule colour: the same rule, held back so it cannot lead the eye.
  static const hairlineFaint = Color(0x8C2F2F35);

  /// Black at 0.55, behind the drawer and behind the open action button.
  static const scrim = Color(0x8C000000);

  // The purple family.

  /// The action button at rest, its expanded pills, a filled button, reading
  /// progress, and a guide drawn onto a white [page], where a light purple
  /// would wash out.
  static const accent = Color(0xFF4F378B);

  /// The action button when open, the spinner, and every purple that has to
  /// hold as a line, a tick or a glyph against a dark ground, where [accent]
  /// sits too near that ground to be seen. On it, text is [onAccentBright].
  static const accentBright = Color(0xFFD0BCFF);

  /// The selected drawer row's pill, and the selected tab's.
  static const accentMuted = Color(0xFF4A4458);

  /// The selected view toggle's fill.
  static const accentPale = Color(0xFFE8DEF8);

  /// [accent] at 0.40, the wash inside a selected cell. The ring round that
  /// cell is [accentBright]: the wash sits under text, the ring does not.
  static const accentWash = Color(0x664F378B);

  /// Text and glyphs on [accent].
  static const onAccent = Color(0xFFFFFFFF);

  /// Text and glyphs on [accentBright] and [accentPale].
  static const onAccentBright = Color(0xFF1D192B);

  // Ink.

  /// Titles, body text, drawer labels, glyphs.
  static const ink = Color(0xFFE6E1E5);

  /// The meta line under a title, sort labels, counts, quoted text.
  static const inkSoft = Color(0xFFCAC4D0);

  /// Row numbers, column letters, placeholder text, disabled glyphs.
  static const inkFaint = Color(0xFF938F99);

  /// A finding: a damaged file, a ragged row, `NO TEXT LAYER`. Only ever this.
  static const damage = Color(0xFFF2B8B5);

  /// The find field's fill when a query has no matches: [surface] carrying a
  /// whisper of [damage]. Derived rather than stated so the two can never
  /// drift apart, and so this stays a tint of the palette's one red rather
  /// than becoming a second red of its own.
  static final damageTint = Color.lerp(surface, damage, 0.14)!;

  /// FOUND: a match tick on the fore edge, at full alpha. One hue means found.
  static const found = Color(0xFFF5C518);

  /// [found] at 0.31, the wash under an ordinary match.
  static const foundWash = Color(0x4FF5C518);

  /// [found] at 0.56, the wash under the current match.
  static const foundLive = Color(0x8FF5C518);

  // The person.

  /// The avatar's ground in the top bar, and the one green in the app.
  ///
  /// It sits outside the purple family on purpose: purple is reserved for the
  /// app acting, and the avatar stands for whoever is holding the phone, which
  /// is the one thing on the bar that is not quire. Its letter is drawn in
  /// [onAccent], because a second white would be a second decision about the
  /// same colour.
  static const avatar = Color(0xFF3B6B45);

  // Paper.

  /// A rendered PDF page, a grid card's thumbnail, and the signature pad,
  /// which is white because the mark made on it is going onto a white page and
  /// has to be the same mark in both places. This is the only white in the
  /// app.
  static const page = Color(0xFFFFFFFF);

  /// Ink on [page]: what the PDF engine paints, and what a signature is drawn
  /// in.
  static const pageInk = Color(0xFF111111);

  /// [pageInk] let down towards the paper, for the body text, the gridlines
  /// and the rules of a thumbnail.
  ///
  /// A page drawn at a third of its size has every line of body text within a
  /// point or two of every other, so setting all of it in solid [pageInk]
  /// turns a document's shape into one block of grey. Holding the body back
  /// from the headings is what lets a title, a table and a paragraph still be
  /// told apart at that size. Derived from the two colours it sits between so
  /// it can never drift away from either.
  static final pageInkSoft = Color.lerp(page, pageInk, 0.45)!;

  /// The back of a sheet, uncovered by a fold, and the alternating row in a
  /// table, which is the same one small step off the sheet. It has to stay
  /// below [surfaceHigh]: the row header column is a control and the striped
  /// rows are not, and a stripe that reached the gutter's value would make
  /// every second row look like part of the gutter.
  static const leafBack = Color(0xFF232329);

  /// The flap: the back of the paper that just turned, one step above
  /// [leafBack] so a fold reads as two thicknesses rather than one grey shape.
  static const leafFlap = Color(0xFF2A2A31);

  // Format chroma. One hue per format, on its type mark and its fore edge
  // ticks and nothing else.

  /// PDF.
  static const fmtPdf = Color(0xFFE8544A);

  /// Word.
  static const fmtDocx = Color(0xFF4285F4);

  /// Excel.
  static const fmtXlsx = Color(0xFF21A366);

  /// CSV.
  static const fmtCsv = Color(0xFFC9832B);

  /// Markdown.
  static const fmtMd = Color(0xFFB39DDB);
}
