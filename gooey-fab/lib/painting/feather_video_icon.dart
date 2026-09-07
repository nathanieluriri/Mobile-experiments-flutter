import 'package:flutter/widgets.dart';

/// The Feather video glyph: a rounded body with a wedge for the lens.
///
/// Drawn rather than taken from the icon font because the packaged glyph is a
/// later redesign of it, a little smaller and with an open lens.
class FeatherVideoIcon extends StatelessWidget {
  const FeatherVideoIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FeatherVideoPainter(color)),
    );
  }
}

/// Strokes the glyph on the 24 unit grid the icon set is drawn on.
class _FeatherVideoPainter extends CustomPainter {
  const _FeatherVideoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1 * unit, 5 * unit, 15 * unit, 14 * unit),
        Radius.circular(2 * unit),
      ),
      stroke,
    );

    final lens = Path()
      ..moveTo(23 * unit, 7 * unit)
      ..lineTo(16 * unit, 12 * unit)
      ..lineTo(23 * unit, 17 * unit)
      ..close();
    canvas.drawPath(lens, stroke);
  }

  @override
  bool shouldRepaint(_FeatherVideoPainter oldDelegate) => oldDelegate.color != color;
}
