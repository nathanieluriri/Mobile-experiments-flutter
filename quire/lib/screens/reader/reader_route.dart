import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/springs.dart';
import 'reader_screen.dart' show kDeskDim;

/// The document coming in, and the desk dimming behind it.
///
/// It is the drawer's motion, on the drawer's spring, from the other side. A
/// document is the same kind of arrival as the panel: a whole surface coming
/// over the one you were on, from the edge it will leave by. The corner button
/// turns from the menu into the arrow across exactly this, which is what makes
/// the two read as one gesture rather than as a glyph animating beside a page.
///
/// The overshoot is clamped. A drawer that springs a little past its mark
/// shows more drawer, and a full screen page that springs past its mark shows
/// the desk down the far edge, which is the page coming unstuck from the side
/// of the screen it is supposed to have arrived from.
final Curve kDocumentArrival = SpringCurve(
  AppSprings.drawer,
  duration: springDuration(AppSprings.drawer, clampOvershoot: true),
  clampOvershoot: true,
);

/// How long that takes, which is the spring's own settling time rather than a
/// number picked to look like it.
final Duration kDocumentArrivalTime = springDuration(
  AppSprings.drawer,
  clampOvershoot: true,
);

/// The route the reader is pushed on.
///
/// It is not opaque, so the desk stays mounted and in position underneath.
/// That is what lets the desk be dimmed rather than covered on the way in, and
/// what lets a back drag reveal the live desk rather than a picture of it.
class ReaderRoute<T> extends PageRouteBuilder<T> {
  ReaderRoute({required WidgetBuilder builder, super.settings})
    : super(
        opaque: false,
        transitionDuration: kDocumentArrivalTime,
        reverseTransitionDuration: kDocumentArrivalTime,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = kDocumentArrival.transform(animation.value.clamp(0.0, 1.0));
        final width = MediaQuery.sizeOf(context).width;
        return Stack(
          children: <Widget>[
            // The dim is under the page and does not travel with it, so the
            // desk darkens where it is standing instead of being followed
            // across the screen by a shadow of itself.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: AppColors.ground.withValues(alpha: kDeskDim * t),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(width * (1 - t), 0),
              child: child,
            ),
          ],
        );
      },
      child: child,
    );
  }
}
