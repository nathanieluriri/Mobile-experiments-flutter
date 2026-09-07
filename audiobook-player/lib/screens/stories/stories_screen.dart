import 'package:flutter/widgets.dart';

import '../../data/playlists.dart';
import '../../data/stories.dart';
import '../../theme/colors.dart';
import '../../theme/layout.dart';
import '../../widgets/story_shelf.dart';
import 'stories_header.dart';

/// The first tab: what is trending, then the playlists.
class StoriesScreen extends StatelessWidget {
  const StoriesScreen({super.key});

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
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StoriesHeader(),
            StoryShelf(title: 'Trending', stories: trendingStories),
            StoryShelf(title: 'Playlists', stories: playlists),
          ],
        ),
      ),
    );
  }
}
