import 'package:flutter/material.dart';

import '../../data/marquee_item.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/card_marquee/card_marquee.dart';
import '../../widgets/pressable_opacity.dart';
import 'onboarding_header.dart';

/// The shape every step of the flow shares: header, title, marquee, and one
/// button pinned above the home indicator.
class OnboardingStepLayout extends StatelessWidget {
  const OnboardingStepLayout({
    super.key,
    required this.step,
    required this.titleLine1,
    required this.titleLine2,
    required this.titleIcon,
    required this.subtitle,
    required this.items,
    required this.ctaIcon,
    required this.ctaLabel,
    required this.ctaColor,
    this.onBack,
    this.onSkip,
    this.onCta,
    this.marqueeController,
  });

  final int step;
  final String titleLine1;
  final String titleLine2;
  final Widget titleIcon;
  final String subtitle;
  final List<MarqueeItem> items;
  final Widget ctaIcon;
  final String ctaLabel;
  final Color ctaColor;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final VoidCallback? onCta;

  /// Supply one to open the marquee somewhere other than its usual slot.
  final ScrollController? marqueeController;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return Material(
      color: AppColors.white,
      child: Padding(
        padding: EdgeInsets.only(top: insets.top),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OnboardingHeader(step: step, onBack: onBack, onSkip: onSkip),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleLine1, style: AppText.headline),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            titleIcon,
                            const SizedBox(width: 10),
                            Text(titleLine2, style: AppText.headline),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(subtitle, style: AppText.body),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: CardMarquee(
                      items: items,
                      controller: marqueeController,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: insets.bottom + 8,
              child: PressableOpacity(
                pressedOpacity: 0.85,
                onTap: onCta,
                child: Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ctaIcon,
                      const SizedBox(width: 8),
                      Text(
                        ctaLabel,
                        style: AppText.button.copyWith(color: ctaColor),
                      ),
                    ],
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
