import 'package:flutter/widgets.dart';

import '../models/story.dart';
import '../theme/colors.dart';
import 'pressable.dart';
import 'story_artwork.dart';

/// One tinted card on a shelf.
class StoryCard extends StatelessWidget {
  const StoryCard({super.key, required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      heldOpacity: 0.85,
      child: SizedBox(
        width: 156,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: story.tint,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              StoryArtwork(asset: story.artwork, size: 140, borderRadius: 17),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Inter sets a little wide at this size, so the titles
                      // carry a touch of negative tracking to stay on one line
                      // inside the card.
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      story.studio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
