import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../constants/dissolve.dart';
import '../constants/interpolation.dart';
import '../widgets/dissolve/dissolve_particles.dart';

/// Draws one card coming apart: an atlas of the card's own pixels, and over it
/// a frost that blurs the card and clears early on.
class DissolvePainter extends CustomPainter {
  DissolvePainter({required this.image, required this.particles, required this.progress})
    : super(repaint: progress);

  final ui.Image image;
  final DissolveParticles particles;
  final Animation<double> progress;

  static final _atlasPaint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) {
    final value = progress.value;

    particles.update(value, size.width);
    canvas.drawRawAtlas(
      image,
      particles.transforms,
      particles.rects,
      particles.colors,
      BlendMode.modulate,
      (Offset.zero & size).inflate(ParticleMotion.windOverscan * 4),
      _atlasPaint,
    );

    final opacity = interpolate(
      value,
      const [0, FrostEffect.hold, FrostEffect.clear],
      const [1, 1, 0],
    );
    if (opacity <= 0) {
      return;
    }
    final sigma = interpolate(
      value,
      const [0, FrostEffect.blurEnd],
      const [0, FrostEffect.maxBlur],
    );
    final card = particles.origin & particles.size;
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (sigma > 0) {
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      );
    }
    canvas.saveLayer(
      card.inflate(FrostEffect.maxBlur * 3),
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      card,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DissolvePainter old) =>
      old.image != image || old.particles != particles || old.progress != progress;
}
