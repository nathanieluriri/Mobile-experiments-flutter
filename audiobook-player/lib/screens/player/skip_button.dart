import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/layout.dart';
import '../../widgets/pressable.dart';

/// Jump back or forward by the skip interval.
class SkipButton extends StatelessWidget {
  const SkipButton({super.key, required this.forward});

  final bool forward;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      heldOpacity: 0.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            forward ? LucideIcons.rotateCw : LucideIcons.rotateCcw,
            size: 36,
            color: AppColors.ink,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${Playback.skipIntervalSeconds}',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
