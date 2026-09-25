import 'package:flutter/widgets.dart';

import '../../models/story.dart';
import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import '../../widgets/play_pause_button.dart';
import '../../widgets/pressable.dart';
import '../../widgets/story_artwork.dart';

/// One saved playlist.
class PlaylistRow extends StatelessWidget {
  const PlaylistRow({super.key, required this.playlist});

  final Story playlist;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      heldOpacity: 0.85,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: playlist.tint,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            StoryArtwork(asset: playlist.artwork, size: 60, borderRadius: 15),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlist.studio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: PlayPauseButton(
                isPlaying: false,
                onPressed: () => PlayerScope.read(context).expandSheet(),
                diameter: 44,
                iconSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
