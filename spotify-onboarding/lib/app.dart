import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      // The flow is drawn on white, so it stays light whatever the system is
      // set to, and the status bar keeps its dark glyphs.
      themeMode: ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.spotify,
          surface: AppColors.white,
        ),
      ),
      home: const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: ColoredBox(color: AppColors.white, child: OnboardingFlow()),
      ),
    );
  }
}
