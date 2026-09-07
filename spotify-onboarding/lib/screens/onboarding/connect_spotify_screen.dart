import 'package:flutter/widgets.dart';

import '../../data/artists.dart';
import '../../theme/colors.dart';
import '../../widgets/icons/spotify_icon.dart';
import 'onboarding_step.dart';
import 'onboarding_step_layout.dart';

/// Step two: link Spotify so the flow can follow the artists you listen to.
class ConnectSpotifyScreen extends StatelessWidget {
  const ConnectSpotifyScreen({
    super.key,
    this.onBack,
    this.onSkip,
    this.onConnect,
    this.marqueeController,
  });

  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final VoidCallback? onConnect;
  final ScrollController? marqueeController;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepLayout(
      step: OnboardingStep.connectSpotify.number,
      titleLine1: 'Connect Your',
      titleLine2: 'Spotify',
      titleIcon: const SpotifyIcon(size: 34, discColor: AppColors.ink),
      subtitle:
          'Link Spotify to track favorite artists and get concert '
          'recommendations tailored to your listening.',
      items: artists,
      ctaIcon: (color) => SpotifyIcon(size: 20, color: color),
      ctaLabel: 'Connect Spotify',
      accent: AppColors.spotify,
      onBack: onBack,
      onSkip: onSkip,
      onCta: onConnect,
      marqueeController: marqueeController,
    );
  }
}
