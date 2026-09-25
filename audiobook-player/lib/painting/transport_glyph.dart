import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Which transport glyph to draw.
enum TransportGlyphKind { play, pause }

/// The play triangle and the pause bars, solid rather than outlined.
///
/// Both are Lucide geometry on a 24 unit grid, drawn filled and stroked in the
/// same colour so the shape carries Lucide's rounded corners and its 2 unit
/// outset.
class TransportGlyph extends StatelessWidget {
  const TransportGlyph({
    super.key,
    required this.kind,
    required this.size,
    required this.color,
  });

  final TransportGlyphKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TransportGlyphPainter(kind: kind, color: color),
      isComplex: false,
    );
  }
}

class _TransportGlyphPainter extends CustomPainter {
  const _TransportGlyphPainter({required this.kind, required this.color});

  final TransportGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = switch (kind) {
      TransportGlyphKind.play => _playPath(),
      TransportGlyphKind.pause => _pausePath(),
    };
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  // Lucide's play, taken from its own path: a triangle with its corners cut to
  // a radius of 2, which the 2 wide stroke then carries out to the edges of the
  // grid, the same 20 units of height the pause bars fill.
  static Path _playPath() => _roundedPolygon(const [
    Offset(5, 1.518),
    Offset(22.971, 12),
    Offset(5, 22.482),
  ], 2);

  static Path _pausePath() => Path()
    ..addRRect(RRect.fromLTRBR(5, 3, 10, 21, const Radius.circular(1)))
    ..addRRect(RRect.fromLTRBR(14, 3, 19, 21, const Radius.circular(1)));

  @override
  bool shouldRepaint(_TransportGlyphPainter old) =>
      old.kind != kind || old.color != color;
}

/// A convex polygon wound clockwise, with every corner cut to [radius].
Path _roundedPolygon(List<Offset> points, double radius) {
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final previous = points[(i - 1 + points.length) % points.length];
    final current = points[i];
    final next = points[(i + 1) % points.length];
    final into = (current - previous) / (current - previous).distance;
    final away = (next - current) / (next - current).distance;
    // Half the turn at this corner sets how far back the arc has to start.
    final turn = math.acos(
      (-into.dx * away.dx - into.dy * away.dy).clamp(-1.0, 1.0),
    );
    final tangent = radius / math.tan(turn / 2);
    final start = current - into * tangent;
    final end = current + away * tangent;
    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    path.arcToPoint(end, radius: Radius.circular(radius));
  }
  path.close();
  path.fillType = ui.PathFillType.nonZero;
  return path;
}
