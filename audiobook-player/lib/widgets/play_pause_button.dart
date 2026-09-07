import 'package:flutter/widgets.dart';

import '../painting/transport_glyph.dart';
import '../theme/colors.dart';
import 'pressable.dart';

/// The black disc that starts and stops playback.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.diameter,
    required this.iconSize,
  });

  final bool isPlaying;
  final VoidCallback onPressed;
  final double diameter;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // The play triangle sits a shade right of centre so it looks centred.
    final nudge = isPlaying ? 0.0 : (iconSize / 8).roundToDouble() / 2;
    return Pressable(
      heldOpacity: 0.8,
      onTap: onPressed,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Transform.translate(
          offset: Offset(nudge, 0),
          child: TransportGlyph(
            kind: isPlaying
                ? TransportGlyphKind.pause
                : TransportGlyphKind.play,
            size: iconSize,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }
}
