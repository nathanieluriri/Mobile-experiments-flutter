import 'package:flutter/widgets.dart';

import 'screens/collection/collection_screen.dart';
import 'screens/player/player_sheet.dart';
import 'screens/playlists/playlists_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/stories/stories_screen.dart';
import 'state/player_controller.dart';
import 'state/player_scope.dart';
import 'theme/colors.dart';
import 'widgets/app_tab_bar.dart';

/// The four tabs, the tab bar, and the player sheet that floats over them.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.start = const PlayerStart(),
    this.initialTab = 0,
  });

  final PlayerStart start;
  final int initialTab;

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late final PlayerController player = PlayerController(
    vsync: this,
    start: widget.start,
  );
  late int _tab = widget.initialTab;

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScope(
      controller: player,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: AppColors.ink,
        ),
        child: ColoredBox(
          color: AppColors.canvas,
          child: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: _tab,
                  children: const [
                    StoriesScreen(),
                    SearchScreen(),
                    CollectionScreen(),
                    PlaylistsScreen(),
                  ],
                ),
              ),
              AppTabBar(
                currentIndex: _tab,
                onSelected: (index) => setState(() => _tab = index),
                sheetProgress: player.sheetProgress,
              ),
              const Positioned.fill(child: PlayerSheet()),
            ],
          ),
        ),
      ),
    );
  }
}
