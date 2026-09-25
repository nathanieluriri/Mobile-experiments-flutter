import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../constants/dissolve.dart';
import '../../constants/interpolation.dart';

/// When one particle starts moving and how far along it is.
///
/// Every particle waits out a delay of its own before it begins, so the sheet
/// comes apart in a sweep rather than all at once. The delay grows with the
/// particle's column, which is what gives the dust its left to right direction.
double particleProgress(double progress, double delaySeed, double columnRatio) {
  final delay = ParticleDelay.base +
      delaySeed * ParticleDelay.jitter +
      columnRatio * ParticleDelay.columnSweep;
  return clamp01((progress - delay) / (1 - delay));
}

/// The buffers one sheet's worth of particles is drawn from.
///
/// The snapshot is cut into [kDissolveTileSize] squares. [rects] names the
/// square each particle carries and never changes. [transforms] and [colors]
/// are rewritten every frame from [update].
class DissolveParticles {
  DissolveParticles({
    required ui.Image image,
    required this.origin,
    required this.size,
    int seed = 0,
    this.motion = ParticleMotionSet.dust,
  })  : cols = (size.width / kDissolveTileSize).ceil(),
        rows = (size.height / kDissolveTileSize).ceil(),
        pixelScale = image.width / size.width {
    _seeds = Float32List(count * kSeedsPerParticle);
    // Fixed so a golden is the same every run, and offset per run so no two
    // sheets come apart along the same paths.
    final random = math.Random(42 + seed);
    for (var i = 0; i < _seeds.length; i++) {
      _seeds[i] = random.nextDouble();
    }

    rects = Float32List(count * 4);
    transforms = Float32List(count * 4);
    colors = Int32List(count);

    final tile = kDissolveTileSize * pixelScale;
    for (var i = 0; i < count; i++) {
      final left = (i % cols) * tile;
      final top = (i ~/ cols) * tile;
      final o = i * 4;
      rects[o] = left;
      rects[o + 1] = top;
      rects[o + 2] = left + tile;
      rects[o + 3] = top + tile;
    }
  }

  /// Where the sheet sits, in the coordinates the overlay paints in.
  final ui.Offset origin;

  /// How big the sheet is, in logical pixels.
  final ui.Size size;

  /// Snapshot pixels per logical pixel.
  final double pixelScale;

  /// Which physics this run uses.
  final ParticleMotionSet motion;

  final int cols;
  final int rows;

  int get count => cols * rows;

  late final Float32List rects;
  late final Float32List transforms;
  late final Int32List colors;
  late final Float32List _seeds;

  /// Rewrites every particle's transform and alpha for [progress], with [width]
  /// the width of the screen the dust is blowing across.
  void update(double progress, double width) {
    for (var i = 0; i < count; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final originX = origin.dx + col * kDissolveTileSize;
      final originY = origin.dy + row * kDissolveTileSize;

      final s = i * kSeedsPerParticle;
      final t = particleProgress(progress, _seeds[s], col / cols);
      final drive = smoothstep(t);
      final tt = t * t;

      final scatterAngle = _seeds[s + 1] * math.pi * 2;
      final scatter =
          (motion.scatterBase + _seeds[s + 2] * motion.scatterJitter) * drive;
      final wind = (width + ParticleMotion.windOverscan - originX) *
          (motion.windBase + _seeds[s + 3] * motion.windJitter) *
          tt;
      final lift = (motion.liftBase + _seeds[s + 4] * motion.liftJitter) * drive;
      final fall =
          (motion.fallBase + _seeds[s + 4] * motion.fallJitter) * tt * tt;
      final wobble = math.sin(
            t *
                (ParticleMotion.wobbleFrequencyBase +
                    _seeds[s + 5] * ParticleMotion.wobbleFrequencyJitter) *
                math.pi,
          ) *
          motion.wobbleAmplitude *
          drive *
          (1 - t);

      final tx = originX + math.cos(scatterAngle) * scatter + wind;
      final ty =
          originY + math.sin(scatterAngle) * scatter - lift + fall + wobble;

      final crumble = t > ParticleMotion.crumbleStart
          ? 1.0
          : t / ParticleMotion.crumbleStart;
      final scale = (1 - ParticleMotion.maxShrink * crumble) / pixelScale;
      final spin = (_seeds[s + 5] - 0.5) * motion.spinRange * drive;

      final o = i * 4;
      transforms[o] = scale * math.cos(spin);
      transforms[o + 1] = scale * math.sin(spin);
      transforms[o + 2] = tx;
      transforms[o + 3] = ty;

      final fadeStart =
          ParticleFade.startBase + _seeds[s + 5] * ParticleFade.startJitter;
      final fade = clamp01((t - fadeStart) / (ParticleFade.end - fadeStart));
      final alpha = 1 - smoothstep(fade);
      colors[i] = ((alpha * 255).round() << 24) | 0x00FFFFFF;
    }
  }
}
