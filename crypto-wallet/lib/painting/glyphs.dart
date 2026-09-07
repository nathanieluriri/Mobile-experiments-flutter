import 'package:flutter/material.dart';

/// The Ethereum diamond, drawn in [color] inside a square of [size].
class EthGlyph extends StatelessWidget {
  const EthGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _EthPainter(color: color),
    );
  }
}

class _EthPainter extends CustomPainter {
  _EthPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);
    final strong = Paint()..color = color;
    final soft = Paint()..color = color.withValues(alpha: 0.6);

    void tri(Offset a, Offset b, Offset c, Paint paint) {
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        paint,
      );
    }

    // Upper diamond half.
    tri(p(0.5, 0.02), p(0.19, 0.53), p(0.5, 0.67), strong);
    tri(p(0.5, 0.02), p(0.5, 0.67), p(0.81, 0.53), soft);
    // Lower point.
    tri(p(0.19, 0.6), p(0.5, 0.78), p(0.5, 0.98), strong);
    tri(p(0.81, 0.6), p(0.5, 0.98), p(0.5, 0.78), soft);
  }

  @override
  bool shouldRepaint(_EthPainter oldDelegate) => oldDelegate.color != color;
}

/// Three stacked rounded bars, the Solana mark.
class SolanaBars extends StatelessWidget {
  const SolanaBars({super.key, required this.barWidth, required this.barHeight, required this.gap});

  final double barWidth;
  final double barHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF00FFA3), Color(0xFF8752F3), Color(0xFFDC1FFF)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) SizedBox(height: gap),
          Container(
            width: barWidth,
            height: barHeight,
            decoration: BoxDecoration(
              color: colors[i],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
