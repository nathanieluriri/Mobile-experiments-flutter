import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../press_fade.dart';

/// One action. It rides its drive value from the button out to its offset,
/// growing and fading in over the last part of the trip, so what leaves the
/// button is goo and what arrives is a labelled pill.
///
/// The pill's round right end stays on the button's centre line at every scale.
/// That is why the scale is taken about the pill's right edge and the position
/// compensates for it: the goo circle under that end never moves sideways, so
/// the neck between the pill and the button stays vertical while the label
/// extends left, out of the goo layer entirely.
///
/// The travel is a change of position rather than a paint transform, so the
/// pill can be tapped where it is drawn.
class FabActionPill extends StatelessWidget {
  const FabActionPill({
    super.key,
    required this.action,
    required this.drive,
    required this.interactive,
    required this.onPressed,
  });

  final FabAction action;
  final Animation<double> drive;

  /// An action that has not opened yet takes no taps, so a closed button is a
  /// single target rather than four stacked on one another.
  final bool interactive;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: drive,
      builder: (context, child) {
        final value = drive.value;
        final scale = interpolateClamped(
          value,
          kActionScaleInput,
          kActionScaleOutput,
        );
        return Positioned(
          right: kFabCanvasWidth - kFabCenterX - kPillRadius * scale,
          top: kFabCenterY + value * action.offsetY - kPillHeight / 2,
          child: IgnorePointer(
            ignoring: !interactive,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: interpolateClamped(
                  value,
                  kActionOpacityInput,
                  kActionOpacityOutput,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: PaperPress(
        onTap: onPressed,
        semanticLabel: action.label,
        child: SizedBox(
          height: kPillHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(kPillRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPillPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    action.glyph,
                    size: kPillGlyphSize,
                    color: AppColors.onAccent,
                  ),
                  const SizedBox(width: kPillGap),
                  Text(
                    action.label,
                    style: AppText.actionPill.copyWith(color: AppColors.onAccent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
