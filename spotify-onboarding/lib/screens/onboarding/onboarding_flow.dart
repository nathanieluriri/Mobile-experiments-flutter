import 'package:flutter/widgets.dart';

import 'connect_spotify_screen.dart';
import 'find_concerts_screen.dart';
import 'onboarding_step.dart';

/// How long a step takes to fade in.
const _fadeIn = Duration(milliseconds: 250);

/// Walks through the steps of the connection flow. A step that arrives fades
/// in; the one it replaces leaves at once.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep _step = OnboardingStep.findConcerts;

  void _go(OnboardingStep step) => setState(() => _step = step);

  @override
  Widget build(BuildContext context) {
    final Widget screen = switch (_step) {
      OnboardingStep.findConcerts => FindConcertsScreen(
        onSkip: () => _go(OnboardingStep.connectSpotify),
        onEnable: () => _go(OnboardingStep.connectSpotify),
      ),
      OnboardingStep.connectSpotify => ConnectSpotifyScreen(
        onBack: () => _go(OnboardingStep.findConcerts),
        onSkip: () => _go(OnboardingStep.connectSpotify),
      ),
    };
    return AnimatedSwitcher(
      duration: _fadeIn,
      reverseDuration: Duration.zero,
      switchInCurve: Curves.easeInOut,
      child: KeyedSubtree(key: ValueKey(_step), child: screen),
    );
  }
}
