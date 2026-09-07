import 'package:flutter/material.dart';

import 'screens/onboarding/onboarding_flow.dart';
import 'theme/colors.dart';
import 'theme/typography.dart';

/// The connection flow.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify Onboarding',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.spotify,
          surface: AppColors.white,
        ),
      ),
      home: const OnboardingFlow(),
    );
  }
}
