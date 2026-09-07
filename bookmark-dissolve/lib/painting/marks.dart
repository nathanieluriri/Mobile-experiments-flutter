import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The small pictorial marks the bookmark previews carry: a sparkle in the Arc
/// tab icon, an apple and a window on the two Arc download buttons, and a
/// rocket at the top of the Notion page. Each is drawn rather than typeset, so
/// it renders the same everywhere.
class Mark extends StatelessWidget {
  const Mark.sparkle({super.key, required this.size, required this.color}) : _paint = _sparkle;

  const Mark.apple({super.key, required this.size, required this.color}) : _paint = _apple;

  const Mark.window({super.key, required this.size, required this.color}) : _paint = _window;

  const Mark.rocket({super.key, required this.size}) : color = null, _paint = _rocket;

  final double size;
  final Color? color;
  final void Function(Canvas canvas, Size size, Color color) _paint;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(_paint, color ?? const Color(0xFF000000)),
      isComplex: false,
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.draw, this.color);

  final void Function(Canvas canvas, Size size, Color color) draw;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size, color);

  @override
  bool shouldRepaint(_MarkPainter old) => old.draw != draw || old.color != color;
}

/// A four pointed star with concave sides.
void _sparkle(Canvas canvas, Size size, Color color) {
  final r = size.width / 2;
  final c = Offset(r, r);
  final waist = r * 0.24;
  final path = Path()..moveTo(c.dx, c.dy - r);
  for (var i = 0; i < 4; i++) {
    final from = i * math.pi / 2 - math.pi / 2;
    final to = from + math.pi / 2;
    final mid = from + math.pi / 4;
    path.quadraticBezierTo(
      c.dx + math.cos(mid) * waist,
      c.dy + math.sin(mid) * waist,
      c.dx + math.cos(to) * r,
      c.dy + math.sin(to) * r,
    );
  }
  canvas.drawPath(path..close(), Paint()..color = color);
}

/// A rounded apple silhouette with a bite and a leaf.
void _apple(Canvas canvas, Size size, Color color) {
  final w = size.width;
  final paint = Paint()..color = color;
  final body = Path()
    ..addRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w * 0.06, w * 0.28, w * 0.88, w * 0.68),
        topLeft: Radius.circular(w * 0.44),
        topRight: Radius.circular(w * 0.44),
        bottomLeft: Radius.circular(w * 0.38),
        bottomRight: Radius.circular(w * 0.38),
      ),
    );
  final notch = Path()
    ..moveTo(w * 0.34, w * 0.26)
    ..quadraticBezierTo(w * 0.5, w * 0.44, w * 0.66, w * 0.26)
    ..close();
  canvas.drawPath(Path.combine(PathOperation.difference, body, notch), paint);
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.52, w * 0.30)
      ..quadraticBezierTo(w * 0.58, w * 0.02, w * 0.86, w * 0.04)
      ..quadraticBezierTo(w * 0.76, w * 0.28, w * 0.52, w * 0.30)
      ..close(),
    paint,
  );
}

/// A square with a plus inside it.
void _window(Canvas canvas, Size size, Color color) {
  final w = size.width;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(w * 0.09, 0.5);
  final box = Rect.fromLTWH(w * 0.08, w * 0.08, w * 0.84, w * 0.84);
  canvas.drawRect(box, stroke);
  canvas.drawLine(Offset(w * 0.5, w * 0.24), Offset(w * 0.5, w * 0.76), stroke);
  canvas.drawLine(Offset(w * 0.24, w * 0.5), Offset(w * 0.76, w * 0.5), stroke);
}

/// A rocket climbing to the upper right, drawn in the emoji's own colours.
void _rocket(Canvas canvas, Size size, Color color) {
  final w = size.width;
  canvas.save();
  canvas.translate(w / 2, w / 2);
  canvas.rotate(math.pi / 4);
  canvas.translate(-w / 2, -w / 2);

  final body = Path()
    ..moveTo(w * 0.5, w * 0.04)
    ..cubicTo(w * 0.82, w * 0.24, w * 0.82, w * 0.56, w * 0.68, w * 0.76)
    ..lineTo(w * 0.32, w * 0.76)
    ..cubicTo(w * 0.18, w * 0.56, w * 0.18, w * 0.24, w * 0.5, w * 0.04)
    ..close();
  canvas.drawPath(body, Paint()..color = const Color(0xFFE8E9EB));

  final fin = Paint()..color = const Color(0xFFE0554A);
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.32, w * 0.52)
      ..lineTo(w * 0.08, w * 0.86)
      ..lineTo(w * 0.32, w * 0.78)
      ..close(),
    fin,
  );
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.68, w * 0.52)
      ..lineTo(w * 0.92, w * 0.86)
      ..lineTo(w * 0.68, w * 0.78)
      ..close(),
    fin,
  );
  canvas.drawCircle(Offset(w * 0.5, w * 0.36), w * 0.13, Paint()..color = const Color(0xFF74B3E0));
  canvas.drawPath(
    Path()
      ..moveTo(w * 0.38, w * 0.78)
      ..quadraticBezierTo(w * 0.5, w * 1.06, w * 0.62, w * 0.78)
      ..close(),
    Paint()..color = const Color(0xFFF5A623),
  );
  canvas.restore();
}
