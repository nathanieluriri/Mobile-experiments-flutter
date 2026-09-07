import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/colors.dart';

/// What dropping a note on a dock button does.
enum NoteAction { delete, archive, share }

class NoteActionConfig {
  const NoteActionConfig(this.icon, this.action, this.accent);

  final IconData icon;
  final NoteAction action;
  final Color accent;

  String get label => switch (action) {
        NoteAction.delete => 'Delete',
        NoteAction.archive => 'Archive',
        NoteAction.share => 'Share',
      };
}

const kNoteActions = <NoteActionConfig>[
  NoteActionConfig(LucideIcons.trash2, NoteAction.delete, AppColors.danger),
  NoteActionConfig(LucideIcons.archive, NoteAction.archive, AppColors.info),
  NoteActionConfig(LucideIcons.share, NoteAction.share, AppColors.success),
];
