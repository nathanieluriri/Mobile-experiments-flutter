import 'package:flutter/widgets.dart';

import '../models/story.dart';
import '../theme/colors.dart';
import 'story_card.dart';

/// A titled row of cards that scrolls sideways.
class StoryShelf extends StatelessWidget {
  const StoryShelf({super.key, required this.title, required this.stories});

  final String title;
  final List<Story> stories;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
            child: Row(
              children: [
                for (var i = 0; i < stories.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  StoryCard(story: stories[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
