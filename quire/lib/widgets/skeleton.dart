import 'package:flutter/widgets.dart';

import '../theme/colors.dart';
import '../theme/metrics.dart';

/// How long a row takes to become its own outline, and to come back.
const kSkeletonFade = Duration(milliseconds: 260);

/// The two values a skeleton is built from: a plate, and the bars where the
/// words go.
const double kSkeletonBar = 12.0;
const double kSkeletonBarSmall = 9.0;
const double kSkeletonRadius = 6.0;

/// What a row looks like while the desk is being read again.
///
/// Not a shimmer. A shimmer is a light source, and this app has none: it is
/// the row with the words taken out of it, drawn in the same values the row
/// itself is drawn in, so the list keeps its rhythm and its weight while it
/// waits. The document comes back into its own outline rather than appearing
/// somewhere new.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kListRowHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: kListRowPaddingX),
      child: Row(
        children: <Widget>[
          const _Block(
            width: kTypeMarkSize,
            height: kTypeMarkSize,
            radius: kTypeMarkRadius,
          ),
          const SizedBox(width: kListMarkGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Block(width: 168, height: kSkeletonBar),
                SizedBox(height: kListTitleGap + 3),
                _Block(width: 104, height: kSkeletonBarSmall, faint: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The same for a card, which is a picture with two lines under it.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(kGridCardRadius),
    ),
    padding: const EdgeInsets.all(kGridCardPadding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _Block(width: kTypeMarkGridSize + 20, height: kTypeMarkGridSize),
        const SizedBox(height: kGridCardPadding),
        const Expanded(child: _Block(width: double.infinity, height: null)),
        const SizedBox(height: kGridCardPadding),
        const _Block(width: 120, height: kSkeletonBar),
        const SizedBox(height: 8),
        const _Block(width: 76, height: kSkeletonBarSmall, faint: true),
      ],
    ),
  );
}

/// One bar of a skeleton.
class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    this.radius,
    this.faint = false,
  });

  final double width;
  final double? height;
  final double? radius;

  /// True for the line under the name, which carries less than the name does
  /// and says so by being quieter, exactly as the real line is.
  final bool faint;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: faint ? AppColors.surface : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(radius ?? kSkeletonRadius),
    ),
  );
}

/// [child] with its own outline over it, crossed between the two by [quiet].
///
/// Both are built the whole time, so nothing is thrown away and rebuilt when
/// the desk comes back: the words fade out of the row and back into it.
class Skeletal extends StatelessWidget {
  const Skeletal({
    super.key,
    required this.quiet,
    required this.skeleton,
    required this.child,
  });

  /// 0 for the thing itself, 1 for its outline.
  final double quiet;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = quiet.clamp(0.0, 1.0);
    if (t <= 0) return child;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Opacity(opacity: t, child: skeleton),
        ),
        Opacity(opacity: 1 - t, child: child),
      ],
    );
  }
}
