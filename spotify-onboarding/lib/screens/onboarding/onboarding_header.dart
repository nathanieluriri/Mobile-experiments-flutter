import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/hit_slop.dart';
import '../../widgets/icons/back_arrow_icon.dart';
import '../../widgets/pressable_opacity.dart';
import 'onboarding_step.dart';

/// Width of the back arrow's tap target.
const _backWidth = 56.0;

/// Gap between the header's controls and the edges of the screen.
const _edgeGap = 16.0;

const _headerHeight = 44.0;
const _arrowHeight = 22.0;

/// Back arrow, step counter, and Skip pill.
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.step,
    this.onBack,
    this.onSkip,
  });

  final int step;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _headerHeight,
      child: Stack(
        children: [
          // The counter reads from the middle of the screen, not from the gap
          // between the two controls.
          Positioned.fill(
            child: Center(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Connection '),
                    TextSpan(
                      text: '\u2014 $step of $kTotalOnboardingSteps',
                      style: AppText.labelMuted,
                    ),
                  ],
                ),
                style: AppText.label,
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              left: _edgeGap,
              top: (_headerHeight - _arrowHeight) / 2,
              width: _backWidth,
              height: _arrowHeight,
              child: HitSlop(
                slop: 12,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: BackArrowIcon(),
                  ),
                ),
              ),
            ),
          Positioned(
            right: _edgeGap,
            top: 0,
            bottom: 0,
            // The outer one reaches out from the full height of the header, so
            // the sides are not cut off; the inner one reaches out from the
            // pill itself, so the top and bottom are measured from the pill
            // rather than from the header.
            child: HitSlop(
              slop: 8,
              child: Center(
                child: HitSlop(
                  slop: 8,
                    child: PressableOpacity(
                    pressedOpacity: 0.7,
                    onTap: onSkip,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: const BoxDecoration(
                        color: AppColors.pill,
                        borderRadius: BorderRadius.all(Radius.circular(9999)),
                      ),
                      child: const Text('Skip', style: AppText.caption),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
