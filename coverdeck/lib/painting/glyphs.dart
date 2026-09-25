import 'package:flutter/rendering.dart';

/// The glyphs the player controls and the list rows use.
enum Glyph { backwardFill, playFill, pauseFill, forwardFill, chevronRight }

/// The three glyphs on the dock.
enum TabGlyph { deck, browse, library }

/// Grid every glyph below is drawn on.
const _grid = 24.0;

/// Paints one of [Glyph] scaled to fill its box.
class GlyphPainter extends CustomPainter {
  const GlyphPainter({required this.glyph, required this.color});

  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _grid, size.height / _grid);
    switch (glyph) {
      case Glyph.playFill:
        canvas.drawPath(
          Path()
            ..moveTo(6.4, 3.8)
            ..lineTo(19.6, 12)
            ..lineTo(6.4, 20.2)
            ..close(),
          Paint()..color = color,
        );
      case Glyph.pauseFill:
        final paint = Paint()..color = color;
        canvas.drawRect(const Rect.fromLTWH(6.4, 3.8, 3.9, 16.4), paint);
        canvas.drawRect(const Rect.fromLTWH(13.7, 3.8, 3.9, 16.4), paint);
      case Glyph.backwardFill:
        canvas.drawPath(_doubleTriangle(-1), Paint()..color = color);
      case Glyph.forwardFill:
        canvas.drawPath(_doubleTriangle(1), Paint()..color = color);
      case Glyph.chevronRight:
        canvas.drawPath(
          Path()
            ..moveTo(9, 4.6)
            ..lineTo(16.4, 12)
            ..lineTo(9, 19.4),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }
    canvas.restore();
  }

  /// The skip glyphs: two filled triangles pointing along [direction].
  Path _doubleTriangle(int direction) {
    final path = Path();
    for (final tip in const [11.6, 2.0]) {
      final x = direction > 0 ? _grid - tip : tip;
      final back = x + direction * -9;
      path
        ..moveTo(x, 12)
        ..lineTo(back, 5.6)
        ..lineTo(back, 18.4)
        ..close();
    }
    return path;
  }

  @override
  bool shouldRepaint(GlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}

/// Paints one of [TabGlyph] scaled to fill its box.
class TabGlyphPainter extends CustomPainter {
  const TabGlyphPainter({required this.glyph, required this.color});

  final TabGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _grid, size.height / _grid);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case TabGlyph.deck:
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(8, 4, 8, 16),
              const Radius.circular(1.5),
            ),
            stroke,
          )
          ..drawLine(const Offset(4.5, 6.5), const Offset(4.5, 17.5), stroke)
          ..drawLine(const Offset(19.5, 6.5), const Offset(19.5, 17.5), stroke);
      case TabGlyph.browse:
        canvas
          ..drawCircle(const Offset(11, 11), 7, stroke)
          ..drawLine(const Offset(16.5, 16.5), const Offset(21, 21), stroke);
      case TabGlyph.library:
        canvas
          ..drawPath(
            Path()
              ..moveTo(9, 18)
              ..lineTo(9, 5)
              ..lineTo(21, 3)
              ..lineTo(21, 16),
            stroke,
          )
          ..drawCircle(const Offset(6, 18), 3, stroke)
          ..drawCircle(const Offset(18, 16), 3, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TabGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
