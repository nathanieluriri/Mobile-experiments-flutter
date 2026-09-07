import 'package:flutter/material.dart';

import 'screens/browse/browse_screen.dart';
import 'screens/deck/deck_screen.dart';
import 'screens/library/library_screen.dart';
import 'theme/colors.dart';
import 'theme/typography.dart';
import 'widgets/bottom_dock.dart';
import 'widgets/coverflow/coverflow_controller.dart';
import 'widgets/tab_bar_controller.dart';

class App extends StatelessWidget {
  const App({super.key, this.deckController});

  /// Deck position, supplied by tests that need to place it precisely.
  final CoverflowController? deckController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coverdeck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: appFontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
      ),
      home: HomeShell(deckController: deckController),
    );
  }
}

/// The three tabs and the dock that switches them.
///
/// Every tab stays mounted, so the deck keeps its position and the lists keep
/// their scroll offset while another tab is on screen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.deckController});

  /// Tab shown first, which tests use to reach a screen without a tap.
  final int initialTab;

  /// Deck position, supplied by tests that need to place it precisely.
  final CoverflowController? deckController;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;
  final _tabBar = TabBarController();

  @override
  void dispose() {
    _tabBar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _tab,
              children: [
                DeckScreen(controller: widget.deckController),
                BrowseScreen(tabBar: _tabBar),
                LibraryScreen(tabBar: _tabBar),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BottomDock(
                  selected: _tab,
                  onSelect: (index) => setState(() => _tab = index),
                  controller: _tabBar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
