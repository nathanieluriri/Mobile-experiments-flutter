import 'package:flutter/material.dart';

import 'screens/chats/chats_screen.dart';
import 'theme/colors.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gooey FAB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        platform: TargetPlatform.iOS,
        scaffoldBackgroundColor: AppColors.canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.ink),
      ),
      home: const ChatsScreen(),
    );
  }
}
