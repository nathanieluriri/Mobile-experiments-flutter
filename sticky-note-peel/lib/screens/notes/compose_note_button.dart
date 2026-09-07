import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/shadows.dart';
import '../../widgets/press_fade.dart';

/// The floating button that starts a new note. It fades back with the rest of
/// the chrome while a note is lifted.
class ComposeNoteButton extends StatelessWidget {
  const ComposeNoteButton({
    super.key,
    required this.dim,
    required this.isInteractive,
    required this.onTap,
  });

  /// 0 when nothing is lifted, 1 when a note is.
  final double dim;

  /// False while a note is lifted, so the button cannot be tapped through the
  /// dimmed chrome even before the fade finishes.
  final bool isInteractive;

  /// What pressing it starts.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !isInteractive,
      child: Opacity(
        opacity: 1 - kChromeDimAmount * dim,
        child: Center(
          child: PressFade(
            onTap: onTap,
            activeOpacity: 0.85,
            semanticLabel: 'New note',
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: AppShadows.composeButton(),
              ),
              child: const Icon(
                LucideIcons.pen,
                size: 20,
                color: AppColors.noteText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
