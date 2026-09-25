import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_arc_item.dart';
import 'package:spotify_onboarding/widgets/card_marquee/marquee_constants.dart';

/// The transform's horizontal slide, taken out of the matrix.
double slideOf(Matrix4 m) => m.storage[12];

/// The transform's lean in degrees, taken out of the matrix.
double tiltOf(Matrix4 m) =>
    math.atan2(m.storage[1], m.storage[0]) * 180 / math.pi;

/// The transform's scale, taken out of the matrix.
double scaleOf(Matrix4 m) =>
    math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);

void main() {
  const viewport = 604.0;

  /// The scroll offset that puts [slot] exactly in the middle of the viewport.
  double centring(int slot) =>
      slot * kMarqueeItemHeight + kMarqueeItemHeight / 2 - viewport / 2;

  test('a card in the middle leans only by its own tilt', () {
    final m = arcTransform(
      slot: 10,
      scrollOffset: centring(10),
      viewportHeight: viewport,
      itemTilt: -5,
    );
    expect(tiltOf(m), moreOrLessEquals(-1, epsilon: 1e-9));
    expect(scaleOf(m), moreOrLessEquals(1, epsilon: 1e-9));
  });

  test(
    'the slide is the arc radius times one minus the cosine of the lean',
    () {
      for (final slot in [6, 8, 10, 12, 14]) {
        final m = arcTransform(
          slot: slot,
          scrollOffset: centring(10),
          viewportHeight: viewport,
          itemTilt: 6,
        );
        final radians = tiltOf(m) * math.pi / 180;
        expect(
          slideOf(m),
          moreOrLessEquals(
            -kArcRadius * (1 - math.cos(radians)),
            epsilon: 1e-6,
          ),
        );
        expect(slideOf(m), lessThanOrEqualTo(0));
      }
    },
  );

  test('a card at the clamp is drawn at its smallest', () {
    // A whole viewport away is two half viewports, well past the 1.2 clamp,
    // where the shrink per half viewport has been applied 1.2 times over.
    final m = arcTransform(
      slot: 10,
      scrollOffset: centring(10) - viewport,
      viewportHeight: viewport,
      itemTilt: 0,
    );
    expect(
      scaleOf(m),
      moreOrLessEquals(
        1 - kCenterDistanceClamp * kMaxScaleShrink,
        epsilon: 1e-9,
      ),
    );
    expect(scaleOf(m), moreOrLessEquals(0.856, epsilon: 1e-9));
  });

  test('scale is symmetric above and below the middle', () {
    for (final away in [40.0, 150.0, 302.0, 500.0]) {
      final above = scaleOf(
        arcTransform(
          slot: 10,
          scrollOffset: centring(10) + away,
          viewportHeight: viewport,
          itemTilt: 0,
        ),
      );
      final below = scaleOf(
        arcTransform(
          slot: 10,
          scrollOffset: centring(10) - away,
          viewportHeight: viewport,
          itemTilt: 0,
        ),
      );
      expect(above, moreOrLessEquals(below, epsilon: 1e-9));
    }
  });

  test('lean keeps growing past the clamp while scale stops', () {
    final far = arcTransform(
      slot: 10,
      scrollOffset: centring(10) - viewport,
      viewportHeight: viewport,
      itemTilt: 0,
    );
    final further = arcTransform(
      slot: 10,
      scrollOffset: centring(10) - viewport * 2,
      viewportHeight: viewport,
      itemTilt: 0,
    );
    expect(tiltOf(further).abs(), greaterThan(tiltOf(far).abs()));
    expect(scaleOf(further), moreOrLessEquals(scaleOf(far), epsilon: 1e-9));
  });

  test('a card a half viewport away leans by the full tilt', () {
    final m = arcTransform(
      slot: 10,
      scrollOffset: centring(10) - viewport / 2,
      viewportHeight: viewport,
      itemTilt: 0,
    );
    expect(tiltOf(m), moreOrLessEquals(kMaxTiltDeg, epsilon: 1e-9));
  });
}
