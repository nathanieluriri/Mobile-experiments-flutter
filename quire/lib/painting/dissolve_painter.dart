import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../constants/dissolve.dart';
import '../widgets/dissolve/dissolve_particles.dart';

/// Draws one sheet coming apart, as an atlas of the sheet's own pixels.
///
/// The idea the effect carries is that a thing is made of the pixels it is
/// drawn from, so it belongs only where structure is genuinely lost or gained.
class DissolvePainter extends CustomPainter {
  DissolvePainter({
    required this.image,
    required this.particles,
    required this.progress,
  }) : super(repaint: progress);

  final ui.Image image;
  final DissolveParticles particles;
  final Animation<double> progress;

  static final _atlasPaint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) {
    particles.update(progress.value, size.width);
    canvas.drawRawAtlas(
      image,
      particles.transforms,
      particles.rects,
      particles.colors,
      BlendMode.modulate,
      (Offset.zero & size).inflate(ParticleMotion.windOverscan * 4),
      _atlasPaint,
    );
  }

  @override
  bool shouldRepaint(DissolvePainter old) =>
      old.image != image ||
      old.particles != particles ||
      old.progress != progress;
}
