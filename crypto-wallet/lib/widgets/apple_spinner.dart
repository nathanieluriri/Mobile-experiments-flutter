import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

const int _dotCount = 10;
const Duration _revolution = Duration(milliseconds: 900);

/// Ten fading dots that step around a circle, shown while the wallet refreshes.
class AppleSpinner extends StatefulWidget {
  const AppleSpinner({super.key, required this.visibility, this.size = 34});

  /// 0 hides the spinner, 1 shows it at full size.
  final double visibility;
  final double size;

  @override
  State<AppleSpinner> createState() => _AppleSpinnerState();
}

class _AppleSpinnerState extends State<AppleSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: _revolution,
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visibility;
    return IgnorePointer(
      child: Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.9 + 0.1 * v,
          child: AnimatedBuilder(
            animation: _rotation,
            builder: (context, _) {
              final step = (_rotation.value * _dotCount).floor() / _dotCount;
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _SpinnerPainter(turn: step),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({required this.turn});

  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = size.width * 0.14;
    final radius = size.width / 2 - dot / 2;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(turn * math.pi * 2);
    final paint = Paint();
    for (var i = 0; i < _dotCount; i++) {
      final angle = i / _dotCount * math.pi * 2 - math.pi / 2;
      paint.color = AppColors.spinnerDot.withValues(
        alpha: 0.18 + 0.82 * i / (_dotCount - 1),
      );
      canvas.drawCircle(
        Offset(radius * math.cos(angle), radius * math.sin(angle)),
        dot / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) => oldDelegate.turn != turn;
}
