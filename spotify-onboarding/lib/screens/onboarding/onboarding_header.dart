import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/icons/back_arrow_icon.dart';
import '../../widgets/pressable_opacity.dart';
import 'onboarding_step.dart';

const _slotWidth = 56.0;

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
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: _slotWidth,
              height: _slotWidth,
              child: onBack == null
                  ? null
                  : PressableOpacity(
                      pressedOpacity: 0.7,
                      onTap: onBack,
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: BackArrowIcon(),
                      ),
                    ),
            ),
            Text.rich(
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
            SizedBox(
              width: _slotWidth,
              child: Align(
                alignment: Alignment.centerRight,
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
          ],
        ),
      ),
    );
  }
}
