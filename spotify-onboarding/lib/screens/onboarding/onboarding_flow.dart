import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'connect_spotify_screen.dart';
import 'find_concerts_screen.dart';
import 'onboarding_step.dart';

/// How long one step takes to hand over to the next.
const kStepTransition = Duration(milliseconds: 600);

/// How far a step drifts sideways as it comes and goes.
const _drift = 36.0;

/// How soft a step goes at the height of the handover.
const _softness = 8.0;

/// How much a step shrinks back as it leaves, and starts from as it arrives.
const _settle = 0.985;

/// Walks through the steps of the connection flow.
///
/// A step does not cut to the next one. The one leaving drifts against the
/// direction of travel, softening as it goes; the one arriving drifts in over
/// it out of the same softness, sharpens, and settles. They overlap the whole
/// way, so the flow reads as one thing moving rather than two pictures
/// swapping.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow>
    with SingleTickerProviderStateMixin {
  /// Rests at the end of a handover, which is a step sitting still in place.
  late final AnimationController _handover = AnimationController(
    vsync: this,
    duration: kStepTransition,
    value: 1,
  );

  OnboardingStep _step = OnboardingStep.findConcerts;
  OnboardingStep? _leaving;
  bool _forward = true;

  @override
  void dispose() {
    _handover.dispose();
    super.dispose();
  }

  void _go(OnboardingStep next) {
    if (next == _step || _handover.isAnimating) {
      return;
    }
    setState(() {
      _leaving = _step;
      _forward = next.number > _step.number;
      _step = next;
    });
    _handover.forward(from: 0).whenComplete(() {
      if (mounted) {
        setState(() => _leaving = null);
      }
    });
  }

  Widget _screen(OnboardingStep step) => switch (step) {
    OnboardingStep.findConcerts => FindConcertsScreen(
      onSkip: () => _go(OnboardingStep.connectSpotify),
      onEnable: () => _go(OnboardingStep.connectSpotify),
    ),
    OnboardingStep.connectSpotify => ConnectSpotifyScreen(
      onBack: () => _go(OnboardingStep.findConcerts),
      onSkip: () => _go(OnboardingStep.connectSpotify),
    ),
  };

  /// Wraps one step in the part of the handover it plays.
  ///
  /// The wrapping never changes shape, only its numbers, so neither step is
  /// rebuilt from scratch part way through and neither marquee loses its
  /// place.
  Widget _layer(OnboardingStep step, {required bool leaving}) {
    final away = _forward ? _drift : -_drift;
    return AnimatedBuilder(
      key: ValueKey(step),
      animation: _handover,
      child: _screen(step),
      builder: (context, child) {
        final t = _handover.value;
        final double opacity;
        final double shift;
        final double scale;
        final double blur;
        if (leaving) {
          // The step on its way out keeps its cover the whole way, so the
          // ground never shows between the two and the handover reads as one
          // picture dissolving into the other rather than a blink of white.
          opacity = 1;
          final path = Curves.easeInOutCubic.transform(t);
          shift = -away * path;
          scale = lerpDouble(1, _settle, path)!;
          blur = _softness * const Interval(0, 0.7).transform(t);
        } else {
          opacity = const Interval(
            0,
            0.8,
            curve: Curves.easeInOut,
          ).transform(t);
          final path = Curves.easeOutCubic.transform(t);
          shift = away * (1 - path);
          scale = lerpDouble(_settle, 1, path)!;
          blur = _softness * (1 - const Interval(0.1, 0.85).transform(t));
        }
        return IgnorePointer(
          ignoring: leaving,
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setTranslationRaw(shift, 0, 0)
                ..scaleByDouble(scale, scale, 1, 1),
              child: ImageFiltered(
                enabled: blur > 0.05,
                imageFilter: ImageFilter.blur(
                  sigmaX: blur,
                  sigmaY: blur,
                  tileMode: TileMode.decal,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (leaving != null) _layer(leaving, leaving: true),
        _layer(_step, leaving: false),
      ],
    );
  }
}
