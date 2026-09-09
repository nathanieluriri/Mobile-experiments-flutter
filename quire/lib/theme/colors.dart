import 'dart:ui';

/// The whole palette. One theme, no dark mode, no toggle. Every value is
/// opaque unless an alpha is written into the hex.
///
/// There are two accents and each has exactly one job: if a pixel is [marker]
/// the app found it, and if a pixel is [thread] you made it or you are
/// standing on it. Nothing else in the app is ever coloured, which is what
/// lets two hundred marks on a page read as density instead of confetti.
abstract final class AppColors {
  /// The desk. Everything sits on it, and it is dark enough that a sheet of
  /// [leaf] reads as lifted against it with no help from anything else.
  static const deskGround = Color(0xFFE5DED2);

  /// The scrim behind the riffle, and the ground showing through a tear.
  static const deskDeep = Color(0xFFD5CEBE);

  /// A sheet: a document page, a card, the pad, the reading surface.
  static const leaf = Color(0xFFFDFBF6);

  /// The alternating spreadsheet row, under one percent darker than [leaf],
  /// which is striping you feel rather than see.
  static const zebra = Color(0xFFF8F4EB);

  /// The reverse of a sheet, seen through a peel where the corner tore away.
  static const leafBack = Color(0xFFF4EFE4);

  /// The flap itself, one step down from [leafBack], so a fold reads as two
  /// thicknesses of paper rather than one grey shape.
  ///
  /// Light passes through paper rather than reflecting off it, so the back of
  /// a lit sheet is warm, not grey. This value is stated, never derived with
  /// [shade].
  static const leafFlap = Color(0xFFEDE6D8);

  /// Header rails, code slabs, the row header column, the parse strip.
  static const panel = Color(0xFFF2ECE0);

  /// Every hairline: gridlines, dividers, the fore edge, the rule between PDF
  /// pages, the signing baseline.
  static const rule = Color(0xFFDDD5C8);

  /// A hairline that must not lead the eye: every table row except the fifth.
  static const ruleFaint = Color(0xFFEBE4D7);

  /// Body text, titles, the current page bar. Warm near black, so it never
  /// reads blue against warm paper.
  static const ink = Color(0xFF1E1B17);

  /// Secondary text, the whole back layer, quoted text.
  static const inkSoft = Color(0xFF57514A);

  /// Metadata, folios, column letters, placeholders, disabled glyphs.
  static const inkFaint = Color(0xFF9A9288);

  /// YOU: reading progress, the current page bar, a dog ear, the selected
  /// chip's underline, the selected cell's ring, the commit pill.
  static const thread = Color(0xFFB23A20);

  /// YOU, as a fill: the selected cell's wash, and nothing else.
  static const threadWash = Color(0x1FB23A20);

  /// FOUND: a match tick on the fore edge, at full alpha.
  static const marker = Color(0xFFE8B22E);

  /// FOUND: the highlighter wash under an ordinary match.
  static const markerWash = Color(0x4FE8B22E);

  /// FOUND: the wash under the current match.
  static const markerLive = Color(0x8FE8B22E);

  /// A drawn signature, and nothing else in the app.
  static const signatureInk = Color(0xFF1F3B63);

  /// A document or a page that will not open, and nothing else.
  static const damage = Color(0xFFB3402F);

  /// The search field's fill when a query has no matches. A whisper of
  /// [damage] in [leaf], not a red error colour, because a search that finds
  /// nothing is a keystroke on the way somewhere.
  static const damageTint = Color(0xFFF7EDE9);

  /// PDF.
  static const fmtPdf = Color(0xFF8C3A2A);

  /// Word.
  static const fmtDocx = Color(0xFF3A4A66);

  /// Excel.
  static const fmtXlsx = Color(0xFF2F5D50);

  /// CSV.
  static const fmtCsv = Color(0xFF5C5330);

  /// Markdown.
  static const fmtMd = Color(0xFF5A4A78);
}

/// Scales every channel of [color] by `1 + amount`, clamped to a byte. A
/// negative amount darkens.
///
/// Kept for parity with the family. No entry in [AppColors] is derived with
/// it: every colour in this palette is stated.
Color shade(Color color, double amount) {
  int channel(double component) =>
      (component * (1 + amount)).round().clamp(0, 255);
  return Color.fromARGB(
    (color.a * 255).round(),
    channel(color.r * 255),
    channel(color.g * 255),
    channel(color.b * 255),
  );
}
