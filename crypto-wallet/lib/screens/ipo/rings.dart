import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models.dart';
import '../../theme/theme.dart';
import '../../widgets/fade_swap_text.dart';

const Duration _orbit = Duration(milliseconds: 3600);

/// A ring that fills to [progress] with a glowing comet orbiting it.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    required this.size,
    required this.progress,
    this.paused = false,
  });

  final double size;
  final double progress;
  final bool paused;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> with TickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _orbitController = AnimationController(
    vsync: this,
    duration: _orbit,
  );

  static const Duration _fillDuration = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _fill.animateTo(widget.progress, duration: _fillDuration, curve: Curves.easeOutCubic);
    if (!widget.paused) {
      _orbitController.repeat();
    }
  }

  @override
  void didUpdateWidget(CountdownRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      _fill.animateTo(widget.progress, duration: _fillDuration, curve: Curves.easeOutCubic);
    }
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _orbitController.stop();
      } else {
        _orbitController.repeat();
      }
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_fill, _orbitController]),
            builder: (context, _) {
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _CountdownPainter(
                  fill: _fill.value,
                  orbit: _orbitController.value * math.pi * 2,
                ),
              );
            },
          ),
          Icon(LucideIcons.clock, size: widget.size * 0.3, color: AppColors.subtle),
        ],
      ),
    );
  }
}

class _CountdownPainter extends CustomPainter {
  _CountdownPainter({required this.fill, required this.orbit});

  final double fill;
  final double orbit;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 5.0;
    final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final center = size.center(Offset.zero);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = AppColors.chip;
    canvas.drawCircle(center, center.dx - inset, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent;
    if (fill > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fill, false, arc);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(orbit);
    canvas.translate(-center.dx, -center.dy);
    final comet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accentPurple;
    final sweep = 52 * math.pi / 180;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint.from(comet)..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawArc(rect, -math.pi / 2, sweep, false, comet);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CountdownPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.orbit != orbit;
}

/// A ring whose colour and fill follow the allocation tier score.
class ProbabilityRing extends StatefulWidget {
  const ProbabilityRing({
    super.key,
    required this.size,
    required this.tier,
    required this.score,
  });

  final double size;
  final AllocationTier tier;
  final double score;

  @override
  State<ProbabilityRing> createState() => _ProbabilityRingState();
}

class _ProbabilityRingState extends State<ProbabilityRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController.unbounded(vsync: this)
    ..animateWith(springTo(Springs.roll, 0, widget.score));

  @override
  void didUpdateWidget(ProbabilityRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
      _fill.animateWith(springTo(Springs.roll, _fill.value, widget.score));
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  static Color _colorFor(double fill) {
    if (fill <= 0.3) {
      return AppColors.loss;
    }
    if (fill <= 0.6) {
      return Color.lerp(AppColors.loss, AppColors.amber, (fill - 0.3) / 0.3)!;
    }
    if (fill <= 0.92) {
      return Color.lerp(AppColors.amber, AppColors.gain, (fill - 0.6) / 0.32)!;
    }
    return AppColors.gain;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _fill,
            builder: (context, _) {
              final fill = _fill.value.clamp(0.0, 1.0);
              return CustomPaint(
                size: Size.square(widget.size),
                painter: _ProbabilityPainter(fill: fill, color: _colorFor(fill)),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeSwapText(
                text: widget.tier.label,
                style: text(16, weight: FontWeight.w700),
                alignment: Alignment.center,
              ),
              Text('probability', style: text(10, color: AppColors.subtle)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProbabilityPainter extends CustomPainter {
  _ProbabilityPainter({required this.fill, required this.color});

  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 7.0;
    final rect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      center.dx - inset,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = AppColors.chip,
    );
    if (fill <= 0) {
      return;
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = math.pi * 2 * fill;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint.from(arc)
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_ProbabilityPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.color != color;
}
