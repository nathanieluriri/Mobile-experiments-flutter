import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'desk_sheet.dart';

/// What the move sheet was dismissed with.
sealed class MoveChoice {
  const MoveChoice();
}

/// Put it in this folder.
class MoveInto extends MoveChoice {
  const MoveInto(this.folder);
  final String folder;
}

/// Take it out of whatever folder it is in.
class MoveOut extends MoveChoice {
  const MoveOut();
}

/// Make a folder and put it in that.
class MoveIntoNew extends MoveChoice {
  const MoveIntoNew();
}

/// Where a document can be filed.
///
/// A folder here is a place on the desk and not a place on the disk. The file
/// does not move, because moving it would break every other thing filed under
/// where it is: the reading position, the stars, the signatures. What changes
/// is which pile it is in.
class MoveSheet extends StatelessWidget {
  const MoveSheet({
    super.key,
    required this.title,
    required this.folders,
    required this.current,
    required this.countIn,
  });

  final String title;
  final List<String> folders;

  /// The folder it is in now, which is marked and cannot be picked again.
  final String? current;

  /// How many documents each folder holds.
  final int Function(String folder) countIn;

  @override
  Widget build(BuildContext context) {
    final current = this.current;
    return DeskSheet(
      title: 'Move $title',
      note: 'A folder is a pile on the desk. The file itself does not move.',
      children: <Widget>[
        DeskSheetRow(
          label: 'New folder',
          icon: LucideIcons.folderPlus,
          onTap: () => Navigator.of(context).pop(const MoveIntoNew()),
        ),
        if (current != null)
          DeskSheetRow(
            label: 'Out of $current',
            icon: LucideIcons.folderMinus,
            note: 'Back onto the open desk',
            onTap: () => Navigator.of(context).pop(const MoveOut()),
          ),
        if (folders.isNotEmpty) const DeskSheetRule(),
        for (final folder in folders)
          DeskSheetRow(
            label: folder,
            icon: folder == current
                ? LucideIcons.folderOpen
                : LucideIcons.folder,
            note: folder == current
                ? 'Where it is now'
                : _held(countIn(folder)),
            enabled: folder != current,
            onTap: () => Navigator.of(context).pop(MoveInto(folder)),
          ),
      ],
    );
  }

  static String _held(int count) => switch (count) {
    0 => 'Empty',
    1 => '1 document',
    _ => '$count documents',
  };
}
