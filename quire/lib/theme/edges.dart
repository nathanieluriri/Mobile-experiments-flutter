import 'package:flutter/widgets.dart';

import 'colors.dart';

/// One physical pixel, in logical units, at this view's device pixel ratio.
///
/// A rule that only has to say "the paper stops here" wants to be the thinnest
/// mark the screen can make. Anything wider stops reading as an edge and
/// starts reading as a frame, which is a much louder thing to put round a
/// page.
double hairline(BuildContext context) =>
    1 / MediaQuery.devicePixelRatioOf(context);

/// The one edge in the app.
///
/// Nothing here casts a shadow, so a surface is told apart from the surface
/// under it by its own value against that ground and, where value alone is not
/// enough, by this hairline. It is drawn in [AppColors.rule], the single tone
/// the palette reserves for a hairline, which makes the outline round a card
/// and the gridline inside a table the same mark at two scales rather than two
/// unrelated greys.
abstract final class AppEdges {
  /// The edge as one side, for a surface that needs a rule on one edge only,
  /// such as a bar rising off the bottom of a sheet.
  static BorderSide side(BuildContext context) =>
      BorderSide(color: AppColors.rule, width: hairline(context));

  /// The edge all the way round.
  ///
  /// On a leaf it goes over the leaf's own content and under its fold: over,
  /// because a grid that paints its header out to the edge would otherwise
  /// bury it, and under, because a corner that has turned down is not paper
  /// any more and must not be outlined as though it were. On floating chrome
  /// it is simply part of the fill's own decoration, since chrome that lands
  /// on body text needs a contour to stay separate from the words.
  static Border all(BuildContext context) =>
      Border.fromBorderSide(side(context));
}
