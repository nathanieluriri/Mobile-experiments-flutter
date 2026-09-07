import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../../theme/palette.dart';
import 'marquee_constants.dart';

/// The blur ramp, bottom edge first: how tall each layer is and how much blur
/// it adds on top of the layers below it. Blurs applied one after another
/// compose in quadrature, so the four layers give standard deviations of 1.5,
/// 3.5, 6.3, and 9.8 as the band approaches the bottom of the screen.
const _layers = <({double height, double sigma})>[
  (height: 160, sigma: 1.48),
  (height: 112, sigma: 3.14),
  (height: 72, sigma: 5.26),
  (height: 36, sigma: 7.51),
];

/// Blurs the cards more and more as they run off the bottom of the marquee,
/// then washes them out into the ground the flow is drawn on.
class MarqueeBottomFade extends StatelessWidget {
  const MarqueeBottomFade({super.key});

  @override
  Widget build(BuildContext context) {
    final ground = AppPalette.of(context).background;
    return IgnorePointer(
      child: SizedBox(
        height: kBottomFadeHeight,
        child: Stack(
          children: [
            for (final layer in _layers)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: layer.height,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: layer.sigma,
                      sigmaY: layer.sigma,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: kBottomGradientHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ground.withValues(alpha: 0),
                      ground.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
