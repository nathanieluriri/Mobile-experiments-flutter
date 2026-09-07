import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';

/// Playback position of the focused album with its start and end times.
///
/// The bar restarts whenever the album changes and runs linearly across the
/// track's length while playing. Pausing leaves it where it stands.
class ProgressBar extends StatefulWidget {
  const ProgressBar({
    super.key,
    required this.playing,
    required this.durationSec,
    required this.resetKey,
  });

  final bool playing;
  final int durationSec;
  final String resetKey;

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.durationSec),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) {
      _progress.forward();
    }
  }

  @override
  void didUpdateWidget(ProgressBar old) {
    super.didUpdateWidget(old);
    _progress.duration = Duration(seconds: widget.durationSec);
    if (widget.resetKey != old.resetKey) {
      _progress.value = 0;
      if (widget.playing) {
        _progress.forward();
      }
      return;
    }
    if (widget.playing != old.playing) {
      if (widget.playing) {
        _progress.forward();
      } else {
        _progress.stop();
      }
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(2)),
          child: SizedBox(
            height: 4,
            child: ColoredBox(
              color: AppColors.track,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress.value,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.label,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('0:00', style: AppText.time),
            Text(formatDuration(widget.durationSec), style: AppText.time),
          ],
        ),
      ],
    );
  }
}

/// Formats [sec] as minutes and zero padded seconds.
String formatDuration(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
