import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';

/// Washes the thumbnails out into the ground as they run off the bottom of the
/// marquee.
///
/// The family blurs the band as well as fading it. quire does not: the app
/// draws no [BackdropFilter] anywhere, because a blur under a reading surface
/// is the one effect that makes text look like a mistake.
class MarqueeBottomFade extends StatelessWidget {
  const MarqueeBottomFade({super.key, this.ground = AppColors.deskDeep});

  final Color ground;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: kBottomFadeHeight,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: kBottomFadeHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ground.withValues(alpha: 0),
                      ground.withValues(alpha: 0.35),
                    ],
                  ),
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
