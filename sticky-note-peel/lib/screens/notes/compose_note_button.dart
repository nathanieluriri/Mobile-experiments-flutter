import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/shadows.dart';

/// The floating button that starts a new note. It fades back with the rest of
/// the chrome while a note is lifted.
class ComposeNoteButton extends StatelessWidget {
  const ComposeNoteButton({super.key, required this.dim});

  final double dim;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: dim > 0,
      child: Opacity(
        opacity: 1 - kChromeDimAmount * dim,
        child: Center(
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
    );
  }
}
