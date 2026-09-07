import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'state/player_controller.dart';

/// The audiobook library and its player.
class App extends StatelessWidget {
  const App({super.key, this.start = const PlayerStart(), this.initialTab = 0});

  /// Where playback stands when the app opens.
  final PlayerStart start;

  /// Which tab is showing when the app opens.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audiobook Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      ),
      home: HomeShell(start: start, initialTab: initialTab),
    );
  }
}
