import 'dart:ui' as ui;

import 'package:bookmark_dissolve/constants/dissolve.dart';
import 'package:bookmark_dissolve/widgets/dissolve/dissolve_particles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// A picture the size of a card, at the phone's pixel ratio.
Future<ui.Image> cardSnapshot(
  WidgetTester tester,
  Size size,
  double pixelRatio,
) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: const ColoredBox(color: Color(0xFF4E4BEC)),
        ),
      ),
    ),
  );
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImageSync(pixelRatio: pixelRatio);
}

void main() {
  const size = Size(192, 204);
  const origin = Offset(228, 78);

  testWidgets('the card is cut into three pixel tiles of its own picture', (
    tester,
  ) async {
    final image = await cardSnapshot(tester, size, 2);
    final particles = DissolveParticles(
      image: image,
      origin: origin,
      size: size,
    );

    expect(particles.cols, 64);
    expect(particles.rows, 68);
    expect(particles.count, 64 * 68);
    expect(particles.pixelScale, 2);

    // Every sprite is one tile of the snapshot, in snapshot pixels.
    const tile = kDissolveTileSize * 2;
    expect(particles.rects.sublist(0, 4), [0, 0, tile, tile]);
    expect(particles.rects.sublist(4, 8), [tile, 0, tile * 2, tile]);
    final secondRow = particles.cols * 4;
    expect(particles.rects.sublist(secondRow, secondRow + 4), [
      0,
      tile,
      tile,
      tile * 2,
    ]);
    image.dispose();
  });

  testWidgets('at the start every tile sits exactly where it was', (
    tester,
  ) async {
    final image = await cardSnapshot(tester, size, 2);
    final particles = DissolveParticles(
      image: image,
      origin: origin,
      size: size,
    )..update(0, 440);

    for (var i = 0; i < particles.count; i++) {
      final o = i * 4;
      // Scale of 1 / pixelScale draws a tile at its original size.
      expect(particles.transforms[o], moreOrLessEquals(0.5));
      expect(particles.transforms[o + 1], 0);
      expect(
        particles.transforms[o + 2],
        moreOrLessEquals(origin.dx + (i % particles.cols) * kDissolveTileSize),
      );
      expect(
        particles.transforms[o + 3],
        moreOrLessEquals(origin.dy + (i ~/ particles.cols) * kDissolveTileSize),
      );
      expect(particles.colors[i] & 0xFFFFFFFF, 0xFFFFFFFF);
    }
    image.dispose();
  });

  testWidgets('by the end every tile has shrunk, faded and blown right', (
    tester,
  ) async {
    final image = await cardSnapshot(tester, size, 2);
    final particles = DissolveParticles(
      image: image,
      origin: origin,
      size: size,
    )..update(1, 440);

    for (var i = 0; i < particles.count; i++) {
      final o = i * 4;
      expect(particles.colors[i] >> 24 & 0xFF, 0);
      // Shrunk by the crumble, and turned by the spin, so the two components
      // of the transform still square to the scale.
      final scale =
          particles.transforms[o] * particles.transforms[o] +
          particles.transforms[o + 1] * particles.transforms[o + 1];
      expect(scale, moreOrLessEquals(0.16 * 0.16, epsilon: 1e-6));
    }

    // The wind grows with the distance to the right edge of the screen, so the
    // left of the card travels much further than the right of it.
    double meanShift(int col) {
      var total = 0.0;
      for (var row = 0; row < particles.rows; row++) {
        final o = (row * particles.cols + col) * 4;
        total +=
            particles.transforms[o + 2] - (origin.dx + col * kDissolveTileSize);
      }
      return total / particles.rows;
    }

    expect(meanShift(0), greaterThan(200));
    expect(meanShift(0), greaterThan(meanShift(particles.cols - 1) * 2));
    image.dispose();
  });

  test('the left of the card starts moving before the right', () {
    // Column sweep: with the same seed, a later column starts later.
    const seed = 0.5;
    expect(
      particleProgress(0.5, seed, 0),
      greaterThan(particleProgress(0.5, seed, 1)),
    );
    // Nothing has begun before the base delay.
    expect(particleProgress(ParticleDelay.base - 0.001, 0, 0), 0);
    expect(particleProgress(1, seed, 1), 1);
  });
}
