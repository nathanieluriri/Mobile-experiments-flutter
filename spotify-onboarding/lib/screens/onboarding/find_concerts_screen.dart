import 'package:flutter/widgets.dart';

import '../../data/cities.dart';
import '../../theme/colors.dart';
import '../../widgets/icons/location_icon.dart';
import 'onboarding_step.dart';
import 'onboarding_step_layout.dart';

/// Step one: ask for location so the flow can show nearby gigs.
class FindConcertsScreen extends StatelessWidget {
  const FindConcertsScreen({
    super.key,
    this.onSkip,
    this.onEnable,
    this.marqueeController,
  });

  final VoidCallback? onSkip;
  final VoidCallback? onEnable;
  final ScrollController? marqueeController;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepLayout(
      step: OnboardingStep.findConcerts.number,
      titleLine1: 'Find Concerts',
      titleLine2: 'Near You',
      titleIcon: const LocationIcon(
        size: 34,
        discColor: AppColors.locationDisc,
      ),
      subtitle:
          'Turn on location to discover gigs, venues and festivals happening '
          'around you.',
      items: cities,
      ctaIcon: (color) => LocationIcon(size: 20, color: color),
      ctaLabel: 'Enable Location',
      accent: AppColors.locationAccent,
      onSkip: onSkip,
      onCta: onEnable,
      marqueeController: marqueeController,
    );
  }
}
