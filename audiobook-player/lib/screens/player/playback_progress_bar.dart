import 'package:flutter/widgets.dart';

import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import 'marching_dashes.dart';

/// How far through the track we are, then dashes for what is left.
class PlaybackProgressBar extends StatelessWidget {
  const PlaybackProgressBar({super.key, required this.playing});

  final bool playing;

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return SizedBox(
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: player.playbackPosition,
              builder: (context, child) => SizedBox(
                width: constraints.maxWidth * player.playbackPosition.value,
                height: 3,
                child: child,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.inkSoft,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            Expanded(child: MarchingDashes(playing: playing, height: 3)),
          ],
        ),
      ),
    );
  }
}
