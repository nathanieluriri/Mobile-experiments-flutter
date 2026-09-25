import 'package:flutter/animation.dart';

/// `1 - (1 - t)^2`.
class EaseOutQuad extends Curve {
  const EaseOutQuad();

  @override
  double transformInternal(double t) => 1 - (1 - t) * (1 - t);
}

/// `1 - (1 - t)^3`.
class EaseOutCubic extends Curve {
  const EaseOutCubic();

  @override
  double transformInternal(double t) {
    final inverse = 1 - t;
    return 1 - inverse * inverse * inverse;
  }
}

/// `2t^2` on the first half, mirrored on the second.
class EaseInOutQuad extends Curve {
  const EaseInOutQuad();

  @override
  double transformInternal(double t) {
    if (t < 0.5) {
      return 2 * t * t;
    }
    final inverse = 1 - t;
    return 1 - 2 * inverse * inverse;
  }
}

const easeOutQuad = EaseOutQuad();
const easeOutCubic = EaseOutCubic();
const easeInOutQuad = EaseInOutQuad();
