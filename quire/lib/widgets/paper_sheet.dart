import 'package:flutter/widgets.dart';

import '../helpers/fold_geometry.dart';
import '../painting/fold_painter.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/shadows.dart';

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
    this.shadows,
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

  /// Defaults to [AppShadows.leafRest]. Pass an empty list for a sheet whose
  /// shadow is drawn by something else, such as a [PaperPress] around it.
  final List<BoxShadow>? shadows;

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
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: shadows ?? AppShadows.leafRest(),
          border: border,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              ?child,
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
