import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// A folder row's own measurements, which follow the document row's so the
/// two lists read as one desk.
const kFolderRowHeight = 68.0;
const kFolderPlate = 44.0;
const kFolderPlateRadius = 12.0;
const kFolderGlyph = 22.0;
const kFolderGap = 14.0;
const kFolderTitleGap = 3.0;

/// The air over the crumb that names the folder you are in.
const kFolderCrumbGap = 4.0;

/// What an empty folder's own panel is built from.
const kEmptyFolderTop = 128.0;
const kEmptyFolderPlate = 72.0;
const kEmptyFolderWidth = 268.0;

/// The folders on the desk, as a list you go into.
///
/// A folder is drawn like a document because it sits in the same list at the
/// same rhythm, with a plate where a document has its type mark. What it says
/// under its name is what it holds, which is the only question a closed
/// folder can answer.
class FolderBody extends StatelessWidget {
  const FolderBody({
    super.key,
    required this.folders,
    required this.countIn,
    required this.onOpen,
    required this.onRemove,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.footer,
  });

  final List<String> folders;
  final int Function(String folder) countIn;
  final ValueChanged<String> onOpen;

  /// Takes the folder away. What was in it goes back on the open desk, which
  /// is what the sheet behind this says before it happens.
  final ValueChanged<String> onRemove;

  final EdgeInsets padding;
  final ScrollController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    return ListView.builder(
      controller: controller,
      padding: padding,
      itemCount: folders.length + (footer == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index >= folders.length) return footer;
        final folder = folders[index];
        return _FolderRow(
          name: folder,
          held: countIn(folder),
          onOpen: () => onOpen(folder),
          onRemove: () => onRemove(folder),
          last: index == folders.length - 1,
        );
      },
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.held,
    required this.onOpen,
    required this.onRemove,
    required this.last,
  });

  final String name;
  final int held;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final bool last;

  String get _label => switch (held) {
    0 => 'Empty',
    1 => '1 document',
    _ => '$held documents',
  };

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onOpen,
      onLongPress: onRemove,
      semanticLabel: name,
      washRadius: kListRowWashRadius,
      child: SizedBox(
        height: kFolderRowHeight,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kListRowPaddingX,
              ),
              child: Row(
                children: [
                  Container(
                    width: kFolderPlate,
                    height: kFolderPlate,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(kFolderPlateRadius),
                    ),
                    child: const Icon(
                      LucideIcons.folder,
                      size: kFolderGlyph,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(width: kFolderGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.rowTitle.copyWith(
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: kFolderTitleGap),
                        Text(
                          _label,
                          style: AppText.docMeta.copyWith(
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.inkFaint,
                  ),
                ],
              ),
            ),
            if (!last)
              const Positioned(
                left: kListRowPaddingX,
                right: 0,
                bottom: 0,
                height: 1,
                child: ColoredBox(color: AppColors.hairlineFaint),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bar that says which folder you are in, and the way back out of it.
class FolderCrumb extends StatelessWidget {
  const FolderCrumb({
    super.key,
    required this.folder,
    required this.held,
    required this.onLeave,
  });

  final String folder;
  final int held;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kListRowPaddingX, 0, kScreenPadding, 0),
      child: Row(
        children: [
          PaperPress(
            onTap: onLeave,
            semanticLabel: 'Out of $folder',
            feel: Feel.tap,
            washRadius: kFolderPlateRadius,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(
                LucideIcons.chevronLeft,
                size: 20,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowTitle.copyWith(color: AppColors.ink),
            ),
          ),
          Text(
            held == 1 ? '1' : '$held',
            style: AppText.docMeta.copyWith(color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// What an empty folder says where it stands.
class EmptyFolderPanel extends StatelessWidget {
  const EmptyFolderPanel({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: kEmptyFolderTop),
    child: Column(
      children: [
        Container(
          width: kEmptyFolderPlate,
          height: kEmptyFolderPlate,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(kFolderPlateRadius + 8),
          ),
          child: const Icon(
            LucideIcons.folderOpen,
            size: 28,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'This folder is empty',
          style: AppText.destinationTitle.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: kEmptyFolderWidth,
          child: Text(
            'Move a document in from its own menu. Press and hold the folder '
            'on the list behind this to take the folder away.',
            textAlign: TextAlign.center,
            style: AppText.destinationBody.copyWith(color: AppColors.inkSoft),
          ),
        ),
      ],
    ),
  );
}
