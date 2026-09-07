import 'package:flutter/material.dart';

import 'screens/notes/notes_screen.dart';
import 'theme/colors.dart';
import 'theme/typography.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticky Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kFontFamily,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.ink,
        colorScheme: const ColorScheme.dark(surface: AppColors.ink),
      ),
      home: const Material(
        color: AppColors.ink,
        // Replaces the framework's default text style, which carries letter
        // spacing this design does not use.
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: kFontFamily,
            fontSize: 14,
            height: kLineHeight,
            color: AppColors.white,
          ),
          child: NotesScreen(),
        ),
      ),
    );
  }
}
