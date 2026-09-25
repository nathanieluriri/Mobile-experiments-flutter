import 'package:flutter/widgets.dart';

import '../painting/glyphs.dart';

/// A square glyph from the player's icon set.
class GlyphIcon extends StatelessWidget {
  const GlyphIcon({
    super.key,
    required this.glyph,
    required this.size,
    required this.color,
  });

  final Glyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: GlyphPainter(glyph: glyph, color: color),
    );
  }
}

/// A 24 point dock glyph.
class TabGlyphIcon extends StatelessWidget {
  const TabGlyphIcon({super.key, required this.glyph, required this.color});

  final TabGlyph glyph;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(24),
      painter: TabGlyphPainter(glyph: glyph, color: color),
    );
  }
}
