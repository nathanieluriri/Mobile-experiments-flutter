import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import '../../widgets/play_pause_button.dart';
import 'playback_progress_bar.dart';
import 'playback_time_labels.dart';
import 'skip_button.dart';

/// Everything below the hero artwork once the sheet is open.
class ExpandedPlayerView extends StatelessWidget {
  const ExpandedPlayerView({super.key, required this.artworkSpacerHeight});

  final double artworkSpacerHeight;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // The footer is pushed to the bottom when there is room and simply runs off
    // the sheet when there is not, which is what the flex layout does.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: artworkSpacerHeight),
                const SizedBox(height: 28),
                Text(
                  player.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  player.track.studio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.sub),
                ),
                const SizedBox(height: 36),
                PlaybackProgressBar(playing: player.isPlaying),
                const PlaybackTimeLabels(),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SkipButton(forward: false),
                    const SizedBox(width: 56),
                    PlayPauseButton(
                      isPlaying: player.isPlaying,
                      onPressed: player.togglePlay,
                      diameter: 64,
                      iconSize: 26,
                    ),
                    const SizedBox(width: 56),
                    const SkipButton(forward: true),
                  ],
                ),
                const Expanded(child: SizedBox.shrink()),
                Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    bottom: bottomInset + 20,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1.0x',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
                      ),
                      Icon(
                        LucideIcons.moonStar,
                        size: 22,
                        color: AppColors.ink,
                      ),
                      Icon(
                        LucideIcons.airplay,
                        size: 22,
                        color: AppColors.accent,
                      ),
                      Icon(
                        LucideIcons.moreHorizontal,
                        size: 22,
                        color: AppColors.ink,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
