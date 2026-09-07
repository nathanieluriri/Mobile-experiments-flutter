import 'package:flutter/widgets.dart';

import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import '../../theme/layout.dart';
import '../../widgets/play_pause_button.dart';

/// The strip that shows what is playing while the sheet is shut.
class MiniPlayerRow extends StatelessWidget {
  const MiniPlayerRow({super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return GestureDetector(
      onTap: player.expandSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: Layout.miniPlayerHeight,
        padding: const EdgeInsets.only(left: 76, right: 20),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.track.studio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.sub,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PlayPauseButton(
              isPlaying: player.isPlaying,
              onPressed: player.togglePlay,
              diameter: 38,
              iconSize: 15,
            ),
          ],
        ),
      ),
    );
  }
}
