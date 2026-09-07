import 'package:flutter/widgets.dart';

/// The glyphs the FAB draws.
enum FeatherGlyph { video, phone, plus }

/// One glyph from the icon set the app draws its buttons with.
///
/// Stroked from the set's own path data on its 24 unit grid rather than taken
/// from an icon font, because the packaged fonts carry later redesigns of the
/// video and phone glyphs.
class FeatherIcon extends StatelessWidget {
  const FeatherIcon(
    this.glyph, {
    super.key,
    required this.size,
    required this.color,
  });

  final FeatherGlyph glyph;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FeatherPainter(glyph, color)),
    );
  }
}

class _FeatherPainter extends CustomPainter {
  const _FeatherPainter(this.glyph, this.color);

  final FeatherGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.save();
    canvas.scale(unit);
    switch (glyph) {
      case FeatherGlyph.video:
        _video(canvas, stroke);
      case FeatherGlyph.phone:
        _phone(canvas, stroke);
      case FeatherGlyph.plus:
        _plus(canvas, stroke);
    }
    canvas.restore();
  }

  static void _video(Canvas canvas, Paint stroke) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 5, 15, 14),
        const Radius.circular(2),
      ),
      stroke,
    );
    final lens = Path()
      ..moveTo(23, 7)
      ..lineTo(16, 12)
      ..lineTo(23, 17)
      ..close();
    canvas.drawPath(lens, stroke);
  }

  static void _phone(Canvas canvas, Paint stroke) {
    const small = Radius.circular(2);
    const wide = Radius.circular(12.84);
    final handset = Path()
      ..moveTo(22, 16.92)
      ..lineTo(22, 19.92)
      ..arcToPoint(const Offset(19.82, 21.92), radius: small)
      ..arcToPoint(
        const Offset(11.19, 18.85),
        radius: const Radius.circular(19.79),
      )
      ..arcToPoint(
        const Offset(5.19, 12.85),
        radius: const Radius.circular(19.5),
      )
      ..arcToPoint(
        const Offset(2.12, 4.18),
        radius: const Radius.circular(19.79),
      )
      ..arcToPoint(const Offset(4.11, 2), radius: small)
      ..lineTo(7.11, 2)
      ..arcToPoint(const Offset(9.11, 3.72), radius: small)
      ..arcToPoint(const Offset(9.81, 6.53), radius: wide, clockwise: false)
      ..arcToPoint(const Offset(9.36, 8.64), radius: small)
      ..lineTo(8.09, 9.91)
      ..arcToPoint(
        const Offset(14.09, 15.91),
        radius: const Radius.circular(16),
        clockwise: false,
      )
      ..lineTo(15.36, 14.64)
      ..arcToPoint(const Offset(17.47, 14.19), radius: small)
      ..arcToPoint(const Offset(20.28, 14.89), radius: wide, clockwise: false)
      ..arcToPoint(const Offset(22, 16.92), radius: small)
      ..close();
    canvas.drawPath(handset, stroke);
  }

  static void _plus(Canvas canvas, Paint stroke) {
    canvas.drawLine(const Offset(12, 5), const Offset(12, 19), stroke);
    canvas.drawLine(const Offset(5, 12), const Offset(19, 12), stroke);
  }

  @override
  bool shouldRepaint(_FeatherPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
