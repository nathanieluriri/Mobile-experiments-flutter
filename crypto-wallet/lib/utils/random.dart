import 'dart:math' as math;

/// Deterministic hash of [seed] into [0, 1).
double seededRandom(double seed) {
  final s = math.sin(seed) * 43758.5453123;
  return s - s.floorToDouble();
}

/// The single random source for every simulated value in the app, seeded so
/// that runs are reproducible.
final appRandom = math.Random(42);
