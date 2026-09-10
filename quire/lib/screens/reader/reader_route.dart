import 'package:flutter/widgets.dart';

import '../../theme/springs.dart';

/// How far in the document is, over the time it takes to arrive.
///
/// The drawer's shape at a page's size, which is [AppSprings.documentArrival].
///
/// The overshoot is clamped. A drawer that springs a little past its mark
/// shows more drawer, and a full screen page that springs past its mark shows
/// the desk down its far edge, which is the page coming unstuck from the side
/// it is supposed to have arrived from. What is given up is four points of
/// wobble, and what is kept is an edge that never opens.
final Curve kDocumentArrival = SpringCurve(
  AppSprings.documentArrival,
  duration: springDuration(AppSprings.documentArrival, clampOvershoot: true),
  clampOvershoot: true,
);

/// How long that takes: the spring's own time to reach the far side, rather
/// than a number picked to look like it.
final Duration kDocumentArrivalTime = springDuration(
  AppSprings.documentArrival,
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

  /// Nothing. The reader carries its own arrival in.
  ///
  /// It has to. A route can only move the whole screen it is given, and what
  /// has to happen here is that the document travels while the band stays
  /// where it is: the button in the corner is the desk's button turning into
  /// an arrow, and a button that slid in from the side of the screen would be
  /// a second button arriving next to the one it is supposed to be.
  ///
  /// So the reader reads this route's animation and slides its own paper, the
  /// same way it already slides it under a back drag. The route's job is the
  /// clock and nothing else.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
