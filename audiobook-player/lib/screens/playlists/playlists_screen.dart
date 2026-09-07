import 'package:flutter/widgets.dart';

import '../../data/playlists.dart';
import '../../theme/colors.dart';
import '../../theme/layout.dart';
import '../../widgets/screen_title.dart';
import 'create_playlist_row.dart';
import 'playlist_row.dart';

/// The fourth tab: every saved playlist, then a row to add one.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    return Container(
      color: AppColors.canvas,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: insets.top + Layout.screenTopPadding,
          bottom:
              Layout.tabBarHeight +
              insets.bottom +
              Layout.miniPlayerHeight +
              Layout.scrollBottomClearance,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenTitle(title: 'Playlists'),
            Padding(
              padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
              child: Column(
                children: [
                  for (final playlist in playlists) ...[
                    PlaylistRow(playlist: playlist),
                    const SizedBox(height: 12),
                  ],
                  const CreatePlaylistRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
