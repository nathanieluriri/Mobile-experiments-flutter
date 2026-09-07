import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';
import 'theme/index.dart';
import 'widgets/dissolve/dissolve_scope.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bookmark Dissolve',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: kFontFamily,
        scaffoldBackgroundColor: AppColors.canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.ink),
      ),
      home: const DissolveScope(
        child: Scaffold(backgroundColor: AppColors.canvas, body: HomeScreen()),
      ),
    );
  }
}
