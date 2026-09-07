/// The steps of the connection flow.
enum OnboardingStep {
  findConcerts(1),
  connectSpotify(2);

  const OnboardingStep(this.number);

  /// Position shown in the header counter.
  final int number;
}

/// The counter promises three steps.
const kTotalOnboardingSteps = 3;
