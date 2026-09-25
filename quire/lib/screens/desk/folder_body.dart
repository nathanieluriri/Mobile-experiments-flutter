import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/device_storage.dart';
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
    this.onMake,
    this.onAdopt,
    this.deviceFolders = const <AdoptedFolder>[],
    this.isMissing,
    this.onOpenDevice,
    this.onDeviceActions,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.footer,
  });

  /// Makes a new folder. The first row of the list, above the folders, the
  /// way a file manager puts it where the folders are.
  final VoidCallback? onMake;

  /// Asks the phone for one of its own folders to read from.
  final VoidCallback? onAdopt;

  final List<String> folders;
  final int Function(String folder) countIn;
  final ValueChanged<String> onOpen;

  /// Asks what to do with the folder: rename it or take it away. A long
  /// press, the way a file manager offers what can be done to a folder.
  final ValueChanged<String> onRemove;

  /// Folders on the phone the reader handed over, listed after quire's own
  /// and behaving the same: tap to go in, hold for what can be done.
  final List<AdoptedFolder> deviceFolders;
  final bool Function(AdoptedFolder folder)? isMissing;
  final ValueChanged<AdoptedFolder>? onOpenDevice;
  final ValueChanged<AdoptedFolder>? onDeviceActions;

  final EdgeInsets padding;
  final ScrollController? controller;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    final rows = <Widget>[
      if (onMake case final make?) NewFolderRow(onTap: make),
      if (onAdopt case final adopt?) AdoptFolderRow(onTap: adopt),
      for (var i = 0; i < folders.length; i++)
        _FolderRow(
          name: folders[i],
          label: _heldLabel(countIn(folders[i])),
          onOpen: () => onOpen(folders[i]),
          onRemove: () => onRemove(folders[i]),
          last: i == folders.length - 1 && deviceFolders.isEmpty,
        ),
      for (var i = 0; i < deviceFolders.length; i++)
        _FolderRow(
          name: deviceFolders[i].name,
          label: (isMissing?.call(deviceFolders[i]) ?? false)
              ? 'Not on the phone any more'
              : 'On the phone',
          icon: LucideIcons.smartphone,
          onOpen: () => onOpenDevice?.call(deviceFolders[i]),
          onRemove: () => onDeviceActions?.call(deviceFolders[i]),
          last: i == deviceFolders.length - 1,
        ),
      ?footer,
    ];
    return ListView(
      controller: controller,
      padding: padding,
      children: rows,
    );
  }
}

String _heldLabel(int held) => switch (held) {
  0 => 'Empty',
  1 => '1 document',
  _ => '$held documents',
};

/// The row that hands one of the phone's own folders to quire. The phone
/// asks which, and quire can read only that folder and what is inside it.
class AdoptFolderRow extends StatelessWidget {
  const AdoptFolderRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PlusRow(
    onTap: onTap,
    label: 'A folder on this phone',
    icon: LucideIcons.smartphone,
  );
}

/// The row that makes a folder, drawn as a folder row with a plus on its
/// plate so it reads as the first place in the list rather than a button
/// laid over it.
class NewFolderRow extends StatelessWidget {
  const NewFolderRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _PlusRow(
    onTap: onTap,
    label: 'New folder',
    icon: LucideIcons.folderPlus,
  );
}

class _PlusRow extends StatelessWidget {
  const _PlusRow({
    required this.onTap,
    required this.label,
    required this.icon,
  });

  final VoidCallback onTap;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      washRadius: kListRowWashRadius,
      child: SizedBox(
        height: kFolderRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kListRowPaddingX),
          child: Row(
            children: [
              Container(
                width: kFolderPlate,
                height: kFolderPlate,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kFolderPlateRadius),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Icon(
                  icon,
                  size: kFolderGlyph,
                  color: AppColors.accentBright,
                ),
              ),
              const SizedBox(width: kFolderGap),
              Text(
                label,
                style: AppText.rowTitle.copyWith(color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One folder in a list of them, quire's own or the phone's.
class DeviceFolderRow extends StatelessWidget {
  const DeviceFolderRow({
    super.key,
    required this.name,
    required this.onOpen,
    this.last = false,
  });

  final String name;
  final VoidCallback onOpen;
  final bool last;

  @override
  Widget build(BuildContext context) => _FolderRow(
    name: name,
    label: 'Folder',
    icon: LucideIcons.folder,
    onOpen: onOpen,
    onRemove: onOpen,
    last: last,
  );
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.label,
    required this.onOpen,
    required this.onRemove,
    required this.last,
    this.icon = LucideIcons.folder,
  });

  final String name;
  final String label;
  final IconData icon;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final bool last;

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
                    child: Icon(
                      icon,
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
                          label,
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
    this.onMore,
  });

  final String folder;
  final int held;
  final VoidCallback onLeave;

  /// What can be done to the folder you are in: rename it or take it away.
  final VoidCallback? onMore;

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
          if (onMore != null)
            PaperPress(
              onTap: onMore,
              semanticLabel: 'What can be done with $folder',
              washRadius: kFolderPlateRadius,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(
                  LucideIcons.ellipsis,
                  size: 20,
                  color: AppColors.inkSoft,
                ),
              ),
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
            'Move a document in from its own menu, under More. The dots '
            'above rename this folder or take it away.',
            textAlign: TextAlign.center,
            style: AppText.destinationBody.copyWith(color: AppColors.inkSoft),
          ),
        ),
      ],
    ),
  );
}

/// What a folder on the phone says when there is nothing to list: it has gone,
/// or it holds nothing quire reads.
class DevicePanel extends StatelessWidget {
  const DevicePanel({
    super.key,
    required this.headline,
    required this.body,
    this.action,
    this.onAction,
  });

  final String headline;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Column(
      children: [
        Text(
          headline,
          textAlign: TextAlign.center,
          style: AppText.destinationTitle.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: kEmptyFolderWidth,
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.destinationBody.copyWith(color: AppColors.inkSoft),
          ),
        ),
        if (action case final label?) ...[
          const SizedBox(height: 20),
          PaperPress(
            onTap: onAction ?? () {},
            semanticLabel: label,
            washRadius: kFolderPlateRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                label,
                style: AppText.rowTitle.copyWith(color: AppColors.accentBright),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
