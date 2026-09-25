
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../edit/pptx_deck.dart';
import '../../../edit/pptx_themes.dart';
import '../../../model/document.dart';
import '../../../theme/colors.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';
import '../../desk/desk_sheet.dart';
import '../../reader/bodies/slide_sheet.dart';
import '../doc_editor.dart' show kTextColours;

/// The weights a border steps through, in points, as Slides offers them.
const List<double> kBorderWeights = <double>[0.5, 1, 1.5, 2.25, 3, 4.5, 6];

/// The dashes a border can take: PowerPoint's name, and what it is called.
const List<(String?, String)> kBorderDashes = <(String?, String)>[
  (null, 'Solid'),
  ('dash', 'Dash'),
  ('sysDot', 'Dot'),
  ('dashDot', 'Dash dot'),
  ('lgDash', 'Long dash'),
];

/// The shapes Insert offers: PowerPoint's preset name, and what it is.
const List<(String, String)> kSlideShapes = <(String, String)>[
  ('rect', 'Rectangle'),
  ('roundRect', 'Rounded rectangle'),
  ('ellipse', 'Oval'),
  ('triangle', 'Triangle'),
  ('rtTriangle', 'Right triangle'),
  ('diamond', 'Diamond'),
  ('parallelogram', 'Parallelogram'),
  ('trapezoid', 'Trapezoid'),
  ('pentagon', 'Pentagon'),
  ('hexagon', 'Hexagon'),
  ('octagon', 'Octagon'),
  ('star5', 'Star'),
  ('star4', 'Four-point star'),
  ('rightArrow', 'Right arrow'),
  ('leftArrow', 'Left arrow'),
  ('upArrow', 'Up arrow'),
  ('downArrow', 'Down arrow'),
  ('chevron', 'Chevron'),
  ('plus', 'Plus'),
  ('heart', 'Heart'),
];

/// A heading inside a sheet.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kDeskSheetPadX, 12, kDeskSheetPadX, 8),
    child: Text(text, style: AppText.label.copyWith(color: AppColors.inkFaint)),
  );
}

/// A row of colour swatches with a None at its head, scrolled sideways so
/// the sheet stays low enough to leave the slide in sight.
class SwatchRow extends StatelessWidget {
  const SwatchRow({super.key, required this.colour, required this.onPick, this.none = 'None'});

  /// 0xAARRGGBB, or null for none.
  final int? colour;

  /// Given 0xFFRRGGBB, or null for none.
  final ValueChanged<int?> onPick;
  final String? none;

  @override
  Widget build(BuildContext context) {
    final picked = colour == null ? null : colour! & 0xFFFFFF;
    Widget swatch(Color? fill, String label, bool chosen, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: PaperPress(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: fill ?? AppColors.surfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: chosen ? AppColors.accentBright : AppColors.hairline, width: chosen ? 3 : 1),
          ),
          child: fill == null ? const Icon(LucideIcons.ban, size: 16, color: AppColors.inkFaint) : null,
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          if (none != null) swatch(null, none!, colour == null, () => onPick(null)),
          for (final (value, name) in kTextColours)
            swatch(Color(0xFF000000 | value), name, value == picked, () => onPick(0xFF000000 | value)),
        ],
      ),
    );
  }
}

/// A row of words to choose one of.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.choices, required this.chosen, required this.onPick});
  final List<(T, String)> choices;
  final T chosen;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        for (final (value, label) in choices)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PaperPress(
              onTap: () => onPick(value),
              semanticLabel: label,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: value == chosen ? AppColors.accent : AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: AppText.label.copyWith(color: value == chosen ? AppColors.onAccent : AppColors.ink),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// One setting of a sheet: its name, and what it offers beside it.
class FormatRow extends StatelessWidget {
  const FormatRow({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(kDeskSheetPadX, 5, 0, 5),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(label, style: AppText.label.copyWith(color: AppColors.inkSoft)),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// Slides' Format options for the thing picked on a slide: its fill, its
/// border's colour, weight and dash, a picture's transparency, and a drop
/// shadow. Each change is made as it is touched, so the slide behind shows
/// it, and each is its own step for Undo.
class ShapeFormatSheet extends StatefulWidget {
  const ShapeFormatSheet({
    super.key,
    required this.deck,
    required this.slide,
    required this.id,
    required this.onChanged,
  });

  final PptxDeck deck;
  final String slide;
  final int id;
  final VoidCallback onChanged;

  @override
  State<ShapeFormatSheet> createState() => _ShapeFormatSheetState();
}

class _ShapeFormatSheetState extends State<ShapeFormatSheet> {
  void _do(void Function(PptxDeck deck, String slide, int id) change) {
    change(widget.deck, widget.slide, widget.id);
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final object = deck.object(widget.slide, widget.id);
    final shape = deck.shape(widget.slide, widget.id);
    if (object == null || shape == null) {
      return const DeskSheet(title: 'Format options', children: <Widget>[]);
    }
    final picture = object.isPicture;
    final line = object.isLine || shape.geometry == 'line';
    final weight = shape.line == null ? 0.0 : (shape.lineWidth <= 0 ? 0.75 : shape.lineWidth);
    return DeskSheet(
      title: 'Format options',
      children: <Widget>[
        if (!picture && !line)
          FormatRow(
            label: 'Fill',
            child: SwatchRow(
              key: const ValueKey<String>('format-fill'),
              colour: shape.fill,
              onPick: (value) => _do((d, s, i) => d.setFill(s, i, value)),
            ),
          ),
        FormatRow(
          label: line ? 'Line' : 'Border',
          child: SwatchRow(
            key: const ValueKey<String>('format-border'),
            colour: shape.line,
            none: line ? null : 'None',
            onPick: (value) => _do((d, s, i) => d.setLineColour(s, i, value)),
          ),
        ),
        FormatRow(
          label: 'Weight',
          child: ChoiceRow<double>(
            choices: <(double, String)>[
              for (final w in kBorderWeights) (w, '${w == w.roundToDouble() ? w.round() : w} pt'),
            ],
            chosen: kBorderWeights.reduce((a, b) => (a - weight).abs() <= (b - weight).abs() ? a : b),
            onPick: (value) => _do((d, s, i) => d.setLineWeight(s, i, value)),
          ),
        ),
        FormatRow(
          label: 'Dashes',
          child: ChoiceRow<String?>(
            choices: kBorderDashes,
            chosen: kBorderDashes.any((d) => d.$1 == shape.dash) ? shape.dash : null,
            onPick: (value) => _do((d, s, i) => d.setLineDash(s, i, value)),
          ),
        ),
        if (picture)
          FormatRow(
            label: 'Transparency',
            child: ChoiceRow<double>(
              choices: const <(double, String)>[(1, '0%'), (0.75, '25%'), (0.5, '50%'), (0.25, '75%')],
              chosen: <double>[1, 0.75, 0.5, 0.25].reduce(
                (a, b) => (a - shape.opacity).abs() <= (b - shape.opacity).abs() ? a : b,
              ),
              onPick: (value) => _do((d, s, i) => d.setOpacity(s, i, value)),
            ),
          ),
        FormatRow(
          label: 'Drop shadow',
          child: ChoiceRow<bool>(
            choices: const <(bool, String)>[(false, 'Off'), (true, 'On')],
            chosen: shape.shadow,
            onPick: (value) => _do((d, s, i) => d.setShadowed(s, i, value)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A preset outline drawn small, for a sheet of shapes.
class OutlineGlyph extends StatelessWidget {
  const OutlineGlyph(this.geometry, {super.key, this.size = 28});
  final String geometry;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * (geometry.contains('Arrow') && !geometry.startsWith('up') && !geometry.startsWith('down') ? 0.7 : 1)),
    painter: _GlyphPainter(slideOutlineOf(geometry)),
  );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.outline);
  final SlideOutline outline;

  @override
  void paint(Canvas canvas, Size size) {
    final path = outline.pathIn(size);
    if (!outline.open) canvas.drawPath(path, Paint()..color = AppColors.accentWash);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.outline != outline;
}

/// The shapes Insert offers, handing back the preset picked.
class ShapePickerSheet extends StatelessWidget {
  const ShapePickerSheet({super.key});

  @override
  Widget build(BuildContext context) => DeskSheet(
    title: 'Shape',
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (name, label) in kSlideShapes)
              PaperPress(
                onTap: () => Navigator.of(context).pop(name),
                semanticLabel: label,
                child: Container(
                  key: ValueKey<String>('shape-$name'),
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: OutlineGlyph(name),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// A small picture of a slide with a name under it, for a sheet of slides
/// to pick from.
class SlideChoice extends StatelessWidget {
  const SlideChoice({
    super.key,
    required this.slide,
    required this.assets,
    required this.label,
    required this.onTap,
    this.chosen = false,
    this.width = 150,
  });

  final SlideBlock slide;
  final Map<String, dynamic> assets;
  final String label;
  final VoidCallback onTap;
  final bool chosen;
  final double width;

  @override
  Widget build(BuildContext context) => PaperPress(
    onTap: onTap,
    semanticLabel: label,
    child: SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: chosen ? AppColors.accentBright : AppColors.hairline,
                width: chosen ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: SlideSheet(slide: slide, assets: assets.cast(), width: width - 4),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.docMeta.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    ),
  );
}

/// The deck's own layouts, handing back the one picked.
class LayoutSheet extends StatelessWidget {
  const LayoutSheet({super.key, required this.deck, required this.title, this.chosen});
  final PptxDeck deck;
  final String title;
  final String? chosen;

  @override
  Widget build(BuildContext context) {
    final assets = deck.assets;
    return DeskSheet(
      title: title,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: <Widget>[
                  for (final layout in deck.layouts)
                    SlideChoice(
                      key: ValueKey<String>('layout-${layout.path}'),
                      slide: deck.layoutPreview(layout.path),
                      assets: assets,
                      label: layout.name,
                      chosen: layout.path == chosen,
                      width: width,
                      onTap: () => Navigator.of(context).pop(layout.path),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// A built-in theme drawn as a small slide: its ground, a title in its
/// words' colour, and its first four accents.
class ThemeCard extends StatelessWidget {
  const ThemeCard({super.key, required this.theme, required this.width});
  final SlideTheme theme;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width - 4,
    height: (width - 4) * 9 / 16,
    color: Color(0xFF000000 | theme.ground),
    padding: EdgeInsets.all(width * 0.07),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Aa',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: width * 0.14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF000000 | theme.ink),
            decoration: TextDecoration.none,
          ),
        ),
        const Spacer(),
        Row(
          children: <Widget>[
            for (final accent in theme.accents.take(4))
              Container(
                width: width * 0.12,
                height: width * 0.05,
                margin: EdgeInsets.only(right: width * 0.03),
                color: Color(0xFF000000 | accent),
              ),
          ],
        ),
      ],
    ),
  );
}

/// What the theme sheet hands back: a master of this deck, or a built-in
/// theme.
typedef ThemePick = ({String? master, SlideTheme? theme});

/// Choose a theme: the deck's own, and the built-in ones.
class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key, required this.deck, required this.current});
  final PptxDeck deck;

  /// The master the current slide is on.
  final String? current;

  @override
  Widget build(BuildContext context) {
    final assets = deck.assets;
    return DeskSheet(
      title: 'Themes',
      children: <Widget>[
        const SheetLabel('In this presentation'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: <Widget>[
                  for (final master in deck.masters)
                    SlideChoice(
                      key: ValueKey<String>('theme-$master'),
                      slide: deck.layoutPreview(deck.layouts.firstWhere((l) => l.master == master).path),
                      assets: assets,
                      label: deck.themeName(master),
                      chosen: master == current,
                      width: width,
                      onTap: () => Navigator.of(context).pop((master: master, theme: null)),
                    ),
                ],
              );
            },
          ),
        ),
        const SheetLabel('Built in'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kDeskSheetPadX),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: <Widget>[
                  for (final theme in kSlideThemes)
                    PaperPress(
                      key: ValueKey<String>('builtin-${theme.name}'),
                      onTap: () => Navigator.of(context).pop((master: null, theme: theme)),
                      semanticLabel: theme.name,
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.hairline),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ThemeCard(theme: theme, width: width),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              theme.name,
                              textAlign: TextAlign.center,
                              style: AppText.docMeta.copyWith(color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
