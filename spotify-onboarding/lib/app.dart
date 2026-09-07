import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/onboarding/onboarding_flow.dart';
import 'theme/app_theme.dart';

/// The connection flow. It follows whatever ground the device is set to.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify Onboarding',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: Builder(
        builder: (context) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            // Glyphs in the status bar read against the ground behind them.
            value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: const OnboardingFlow(),
          );
        },
      ),
    );
  }
}
