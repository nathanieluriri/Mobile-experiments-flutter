/// Side of one square particle, in logical pixels.
const kDissolveTileSize = 3.0;

/// How long a card takes to come apart.
const kDissolveDuration = Duration(milliseconds: 3000);

/// How long a card takes to reassemble.
const kMaterializeDuration = Duration(milliseconds: 1200);

/// Random numbers each particle draws.
const kSeedsPerParticle = 6;

/// When a particle starts moving, as a fraction of the whole run.
abstract final class ParticleDelay {
  static const base = 0.06;
  static const jitter = 0.26;
  static const columnSweep = 0.08;
}

/// How a particle travels once it starts.
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

/// The blur that sits over the card while it comes apart.
abstract final class FrostEffect {
  static const maxBlur = 16.0;
  static const blurEnd = 0.22;
  static const hold = 0.08;
  static const clear = 0.3;
}
