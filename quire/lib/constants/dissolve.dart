/// Side of one square particle, in logical pixels.
const kDissolveTileSize = 3.0;

/// Random numbers each particle draws.
const kSeedsPerParticle = 6;

/// When a particle starts moving, as a fraction of the whole run.
abstract final class ParticleDelay {
  static const base = 0.06;
  static const jitter = 0.26;
  static const columnSweep = 0.08;
}

/// How a particle travels once it starts. House values, unchanged.
abstract final class ParticleMotion {
  static const scatterBase = 14.0;
  static const scatterJitter = 70.0;
  static const windOverscan = 80.0;
  static const windBase = 0.45;
  static const windJitter = 0.75;
  static const liftBase = 6.0;
  static const liftJitter = 38.0;
  static const fallBase = 50.0;
  static const fallJitter = 160.0;
  static const wobbleFrequencyBase = 6.0;
  static const wobbleFrequencyJitter = 6.0;
  static const wobbleAmplitude = 6.0;
  static const crumbleStart = 0.45;
  static const maxShrink = 0.68;
  static const spinRange = 2.5;
}

/// When a particle starts to fade and when it is gone.
abstract final class ParticleFade {
  static const startBase = 0.5;
  static const startJitter = 0.38;
  static const end = 0.97;
}

/// One set of travel constants, so the same atlas and the same painter can run
/// two different physics.
///
/// A card leaving the desk is paper going to fibre and its dust blows across
/// the screen. A signature setting into a page is a mark becoming part of the
/// sheet, so its grains must not blow anywhere: they sink.
class ParticleMotionSet {
  const ParticleMotionSet({
    required this.scatterBase,
    required this.scatterJitter,
    required this.windBase,
    required this.windJitter,
    required this.liftBase,
    required this.liftJitter,
    required this.fallBase,
    required this.fallJitter,
    required this.wobbleAmplitude,
    required this.spinRange,
  });

  final double scatterBase;
  final double scatterJitter;
  final double windBase;
  final double windJitter;
  final double liftBase;
  final double liftJitter;
  final double fallBase;
  final double fallJitter;
  final double wobbleAmplitude;
  final double spinRange;

  /// A card coming apart, or gathering back.
  static const dust = ParticleMotionSet(
    scatterBase: ParticleMotion.scatterBase,
    scatterJitter: ParticleMotion.scatterJitter,
    windBase: ParticleMotion.windBase,
    windJitter: ParticleMotion.windJitter,
    liftBase: ParticleMotion.liftBase,
    liftJitter: ParticleMotion.liftJitter,
    fallBase: ParticleMotion.fallBase,
    fallJitter: ParticleMotion.fallJitter,
    wobbleAmplitude: ParticleMotion.wobbleAmplitude,
    spinRange: ParticleMotion.spinRange,
  );

  /// A signature sinking into the page it was placed on.
  static const absorb = ParticleMotionSet(
    scatterBase: 4,
    scatterJitter: 18,
    windBase: 0.05,
    windJitter: 0.1,
    liftBase: 0,
    liftJitter: 6,
    fallBase: 0,
    fallJitter: 12,
    wobbleAmplitude: 1.5,
    spinRange: 0.3,
  );
}
