import 'package:flutter/widgets.dart';

import '../screens/reader/bodies/page_states.dart';
import '../theme/colors.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';

/// The smallest slot worth tearing. Below this a torn leaf is a smudge, so the
/// surface is drawn as paper with nothing on it instead.
const kDamagedLeast = 80.0;

/// What the reader sees where a piece of the app would not build.
const String kSurfaceDamagedLabel = 'THIS WILL NOT DRAW';

/// The app's own answer to a widget that threw while it was being built.
///
/// Flutter's answer in release is a grey box with nothing in it, sized to
/// whatever slot the broken thing was in. On a desk of paper that reads as a
/// rendering fault, which is exactly what it is, but it tells the reader
/// nothing and it does not look like this app. The same torn leaf a page that
/// will not open already wears says the same thing in the app's own voice.
///
/// It carries its own [Directionality] and takes nothing from the tree above
/// it, because the thing that threw may have been that tree: a replacement
/// that needs an inherited widget to draw can fail while replacing a failure,
/// and that loop has no bottom.
class DamagedSurface extends StatelessWidget {
  const DamagedSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.ground,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : kScreenWidth;
            final height = constraints.hasBoundedHeight
                ? constraints.maxHeight
                : kScreenHeight;
            if (width < kDamagedLeast || height < kDamagedLeast) {
              // Too small to tear. A hairline says the surface is missing
              // without pretending to be a page.
              return const SizedBox.expand(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.leafBack),
                ),
              );
            }
            return Center(
              child: TornPage(
                size: Size(width, height),
                label: kSurfaceDamagedLabel,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The line under a damaged surface, for anything that wants to say the same
/// thing in a row of text rather than as a leaf.
class DamagedLine extends StatelessWidget {
  const DamagedLine({super.key, this.label = kSurfaceDamagedLabel});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textDirection: TextDirection.ltr,
      style: AppText.micro.copyWith(color: AppColors.damage),
    );
  }
}
