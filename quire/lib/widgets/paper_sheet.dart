import 'package:flutter/widgets.dart';

import '../helpers/fold_geometry.dart';
import '../painting/fold_painter.dart';
import '../theme/colors.dart';
import '../theme/edges.dart';
import '../theme/metrics.dart';

/// A leaf of paper: the one rectangle every surface in the app is made of.
///
/// The bottom right corner is square while the other three round by
/// [kLeafRadius], because a folded corner cannot be rounded. That single
/// asymmetry is how a sheet announces it can be turned over, before anyone
/// touches it.
class PaperSheet extends StatelessWidget {
  const PaperSheet({
    super.key,
    this.width,
    this.height,
    this.color = AppColors.leaf,
    this.borderRadius = kPeelableCorner,
    this.border,
    this.foldInset,
    this.foldCorner = Corner.bottomRight,
    this.foldBackground = AppColors.deskGround,
    this.foldColor = AppColors.leafFlap,
    this.foldBackLayer,
    this.foldShowThrough,
    this.child,
  });

  final double? width;
  final double? height;
  final Color color;
  final BorderRadius borderRadius;

  /// The hairline that tells the paper from the ground it is lying on.
  /// Defaults to [AppEdges.all]. Pass a different one for a leaf that wants a
  /// different edge, never null, because a leaf with no edge is a hole.
  final BoxBorder? border;

  /// How far in the resting fold sits, or null for a sheet with no fold.
  final double? foldInset;

  final Corner foldCorner;

  /// What shows through where the corner has torn away.
  final Color foldBackground;
  final Color foldColor;

  /// What the sheet holds on its back, drawn into the torn away region.
  final CustomPainter? foldBackLayer;

  /// The sheet's own front, redrawn on the flap mirrored about the fold line.
  final CustomPainter? foldShowThrough;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              ?child,
              // Over the content and under the fold. Over, because a body that
              // paints its own ground out to the edge would otherwise bury the
              // rule; under, because a turned corner is not paper any more and
              // must not be outlined as though it were.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: border ?? AppEdges.all(context),
                    ),
                  ),
                ),
              ),
              if (foldInset case final inset?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: FoldPainter.atRest(
                        restInset: inset,
                        corner: foldCorner,
                        background: foldBackground,
                        flapColor: foldColor,
                        backLayer: foldBackLayer,
                        showThrough: foldShowThrough,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
