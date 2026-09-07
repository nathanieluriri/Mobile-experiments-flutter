/// Clamps [value] to the unit range.
double clamp01(double value) => value < 0
    ? 0
    : value > 1
    ? 1
    : value;

/// The Hermite ease both the particle motion and the particle fade run through.
double smoothstep(double t) => t * t * (3 - 2 * t);
