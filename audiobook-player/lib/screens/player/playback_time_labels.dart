import 'package:flutter/widgets.dart';

import '../../state/player_scope.dart';
import '../../theme/colors.dart';
import '../../theme/layout.dart';

/// Elapsed on the left, what is left on the right.
class PlaybackTimeLabels extends StatelessWidget {
  const PlaybackTimeLabels({super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AnimatedBuilder(
        animation: player.playbackPosition,
        builder: (context, child) {
          final elapsed = player.positionSeconds.floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPlaybackTime(elapsed.toDouble()),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.subStrong,
                ),
              ),
              Text(
                '-${formatPlaybackTime((Playback.trackDurationSeconds - elapsed).toDouble())}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.sub,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Seconds as `m:ss`.
String formatPlaybackTime(double totalSeconds) {
  final seconds = totalSeconds.round().clamp(0, 1 << 30);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
