import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../constants/gooey_fab.dart' hide kPillRadius;
import '../theme/colors.dart';
import '../theme/feedback.dart';
import '../theme/metrics.dart';
import '../theme/typography.dart';
import 'press_fade.dart';

/// How far apart the pills sit at rest, centre to centre.
const kOverflowPillGap = 62.0;

/// Where the first pill comes to rest, measured from the dots it came out of.
const kOverflowPillFirst = 50.0;

/// The dots' own circle in the goo, which every pill is pulled out of.
const kOverflowDotsBlob = 20.0;

/// The pills' circles in the goo, a little inside the pills drawn over them.
const kOverflowPillBlob = 46.0;

/// Room left round the goo canvas for the origin blob and the blur, so the
/// body is not cut off at the edge of the box the pills are laid out in.
const kOverflowGooPad = 42.0;

/// One thing a goo menu offers.
class GooMenuItem {
  const GooMenuItem({
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final String label;
  final IconData icon;

  /// True for an item that changes what exists rather than what is shown,
  /// which is what sets it in the accent and gives it the heavier feel.
  final bool destructive;
}

/// A menu as separate pills, each peeled off the control that opened it.
///
/// The app's one menu shape, used by the desk's three dots and the reader's:
/// a body per item, joined to the dots by a neck that thins as it travels and
/// then lets go, made of the same goo as the action button.
///
/// It places itself. The dots are the one fixed point in the whole effect, so
/// everything here is measured from their centre: the pills hang off a spine
/// that runs straight down through it, and the goo's origin sits on it
/// exactly, with no box or margin between the two that could move one without
/// the other.
class GooMenu extends StatelessWidget {
  const GooMenu({
    super.key,
    required this.drives,
    required this.items,
    required this.onPick,
    required this.anchor,
    required this.bounds,
  });

  /// How far out each pill is, 0 parked on the dots and 1 at rest, straight
  /// from the springs that carry it.
  ///
  /// Not a clock. The action button's controller runs each pill on its own
  /// simulation until that spring has physically settled, which is what gives
  /// it a swing past its mark and a return; a value sampled off a timer would
  /// be cut off wherever the timer ran out, mid swing. The list may be longer
  /// than [items]; the extra drives belong to items this menu does not offer
  /// this time and are simply not read.
  final List<double> drives;

  final List<GooMenuItem> items;

  /// Called with the index of the pill that was pressed.
  final ValueChanged<int> onPick;

  /// The dots, in the coordinates of the stack this sits in.
  final Rect anchor;

  /// The part of that stack the pills may occupy.
  final Rect bounds;

  /// How tall the run of pills is from the dots to the far edge of the last.
  double get _run => kOverflowPillFirst + (items.length - 1) * kOverflowPillGap;

  /// True when the run goes up from the dots because it cannot go down.
  bool get _upward =>
      anchor.center.dy + _run + kPillHeight / 2 > bounds.bottom &&
      anchor.center.dy - _run - kPillHeight / 2 >= bounds.top;

  @override
  Widget build(BuildContext context) {
    final sign = _upward ? -1.0 : 1.0;
    final height = _run + kPillHeight / 2;
    // The spine sits half a pill in from the box's right edge, so a pill's
    // rounded end wraps the blob it grew out of rather than stopping short
    // of it or running past it.
    final spineX = kSortMenuWidth - kPillHeight / 2;
    // Each pill's centre, measured from the dots along the spine.
    final along = <double>[
      for (var i = 0; i < items.length; i++)
        drives[i] * (kOverflowPillFirst + i * kOverflowPillGap),
    ];
    // In the box, the dots are at the top when the run goes down and at the
    // bottom when it goes up.
    final originY = _upward ? height : 0.0;
    return Positioned(
      left: anchor.center.dx + kPillHeight / 2 - kSortMenuWidth,
      top: _upward ? anchor.center.dy - height : anchor.center.dy,
      width: kSortMenuWidth,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -kOverflowGooPad,
            right: -kOverflowGooPad,
            top: -kOverflowGooPad,
            bottom: -kOverflowGooPad,
            child: IgnorePointer(
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(kGooAlphaThresholdMatrix),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: kGooBlurSigma,
                    sigmaY: kGooBlurSigma,
                    tileMode: TileMode.decal,
                  ),
                  child: CustomPaint(
                    painter: _PillGooPainter(
                      origin: Offset(
                        spineX + kOverflowGooPad,
                        originY + kOverflowGooPad,
                      ),
                      centresY: <double>[
                        for (final a in along)
                          originY + sign * a + kOverflowGooPad,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Furthest first, so the pill nearest the dots is the one on top
          // while they are all still stacked over each other.
          for (var i = items.length - 1; i >= 0; i--)
            Positioned(
              right: 0,
              top: originY + sign * along[i] - kPillHeight / 2,
              child: Opacity(
                opacity: interpolateClamped(
                  drives[i],
                  kActionOpacityInput,
                  kActionOpacityOutput,
                ),
                child: Transform.scale(
                  scale: interpolateClamped(
                    drives[i],
                    kActionScaleInput,
                    kActionScaleOutput,
                  ),
                  alignment: Alignment.centerRight,
                  child: _Pill(item: items[i], onTap: () => onPick(i)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.item, required this.onTap});

  final GooMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final destructive = item.destructive;
    return PaperPress(
      onTap: onTap,
      semanticLabel: item.label,
      feel: destructive ? Feel.commit : Feel.tap,
      child: SizedBox(
        height: kPillHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: destructive ? AppColors.accent : AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(kPillRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPillPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.icon,
                  size: kPillGlyphSize,
                  color: destructive ? AppColors.onAccent : AppColors.ink,
                ),
                const SizedBox(width: kPillGap),
                Text(
                  item.label,
                  style: AppText.actionPill.copyWith(
                    color: destructive ? AppColors.onAccent : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dots' blob, a blob per pill, and the necks between them.
///
/// Every circle sits on the spine that runs through the dots, because that is
/// where the body is being pulled from, and a neck that leans is a neck
/// something has dragged sideways.
class _PillGooPainter extends CustomPainter {
  const _PillGooPainter({required this.origin, required this.centresY});

  /// The dots, in this canvas's coordinates.
  final Offset origin;

  /// Each pill's centre, on the same vertical line as [origin].
  final List<double> centresY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.surfaceHigh;
    canvas.drawCircle(origin, kOverflowDotsBlob, paint);
    for (final centreY in centresY) {
      _neck(canvas, paint, centreY);
      canvas.drawCircle(
        Offset(origin.dx, centreY),
        kOverflowPillBlob / 2,
        paint,
      );
    }
  }

  /// The same tapering run of circles the action button uses, so every menu
  /// in the app is made of one material.
  void _neck(Canvas canvas, Paint paint, double centreY) {
    final travelled = (centreY - origin.dy).abs();
    if (travelled <= 0 || travelled >= kGooNeckBreak) return;
    final left = 1 - travelled / kGooNeckBreak;
    for (var i = 1; i <= kGooNeckCircles; i++) {
      final along = i / (kGooNeckCircles + 1);
      final waist = 1 - (1 - kGooNeckWaist) * math.sin(along * math.pi);
      final radius = ui.lerpDouble(
            kOverflowDotsBlob,
            kOverflowPillBlob / 2,
            along,
          )! *
          waist *
          left;
      if (radius <= 0) continue;
      canvas.drawCircle(
        Offset(origin.dx, ui.lerpDouble(origin.dy, centreY, along)!),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PillGooPainter oldDelegate) {
    if (oldDelegate.origin != origin) return true;
    if (oldDelegate.centresY.length != centresY.length) return true;
    for (var i = 0; i < centresY.length; i++) {
      if (oldDelegate.centresY[i] != centresY[i]) return true;
    }
    return false;
  }
}
