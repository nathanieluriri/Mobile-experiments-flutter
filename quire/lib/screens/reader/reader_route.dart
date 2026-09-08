import 'package:flutter/widgets.dart';

import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import 'sheet_surface.dart';

/// The route the reader is pushed on.
///
/// It is not opaque, so the desk stays mounted and in position underneath.
/// That is what lets a card grow into the sheet without anything being
/// measured offstage, and what lets a back drag reveal the live desk rather
/// than a picture of it.
class ReaderRoute<T> extends PageRouteBuilder<T> {
  ReaderRoute({required WidgetBuilder builder, this.from, super.settings})
    : super(
        opaque: false,
        transitionDuration: kOpenDocument,
        reverseTransitionDuration: kCloseDocument,
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
      );

  /// The card's rect on the desk, which the sheet grows out of. Null opens the
  /// reader without a card behind it, which is what a deep link does.
  final Rect? from;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final origin = from;
    if (origin == null) {
      return FadeTransition(opacity: animation, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = easeOutCubic.transform(animation.value.clamp(0, 1));
        final rect = Rect.lerp(origin, kSheetRect, t)!;
        return Opacity(
          opacity: t,
          child: Transform(transform: growth(rect), child: child),
        );
      },
      child: child,
    );
  }

  /// The matrix that puts the reading sheet exactly on [rect].
  ///
  /// The whole reader is transformed rather than the sheet alone, so the fore
  /// edge, the chip and the chrome arrive with the page instead of being
  /// animated one at a time and disagreeing about where the sheet is.
  static Matrix4 growth(Rect rect) {
    final sx = rect.width / kSheetRect.width;
    final sy = rect.height / kSheetRect.height;
    return Matrix4.identity()
      ..translateByDouble(
        rect.left - kSheetRect.left * sx,
        rect.top - kSheetRect.top * sy,
        0,
        1,
      )
      ..scaleByDouble(sx, sy, 1, 1);
  }
}
