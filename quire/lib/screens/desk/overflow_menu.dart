import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../theme/colors.dart';
import '../../theme/feedback.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// Everything a document can have done to it that is not reading it.
enum DeskAction {
  read(label: 'Open', icon: LucideIcons.bookOpen),
  sign(label: 'Sign', icon: LucideIcons.penLine),
  share(label: 'Share signed', icon: LucideIcons.share2),
  dogEar(label: 'Dog ear', icon: LucideIcons.bookmark),
  star(label: 'Star', icon: LucideIcons.star),
  unstar(label: 'Unstar', icon: LucideIcons.starOff),
  remove(label: 'Remove', icon: LucideIcons.trash2),
  restore(label: 'Put back', icon: LucideIcons.archiveRestore),
  deleteForever(label: 'Delete for good', icon: LucideIcons.trash);

  const DeskAction({required this.label, required this.icon});

  final String label;
  final IconData icon;

  /// True when this action changes what is on the desk rather than what is
  /// on the screen, which is what sets it in the accent.
  bool get destructive =>
      this == DeskAction.remove || this == DeskAction.deleteForever;

  /// True when this action means anything for [entry] as it stands.
  ///
  /// Only a PDF carries a signature, so offering to sign a spreadsheet would
  /// be offering something the app would then have to refuse. A document in
  /// the bin can be read, put back, or deleted, and nothing else: starring
  /// something you have thrown away is not a thing.
  bool suits(
    LibraryEntry entry, {
    required bool starred,
    required bool binned,
    required bool signed,
  }) =>
      switch (this) {
        DeskAction.read => true,
        DeskAction.sign => !binned && entry.format == DocFormat.pdf,
        DeskAction.share =>
          !binned && signed && entry.format == DocFormat.pdf,
        DeskAction.dogEar => !binned,
        DeskAction.star => !binned && !starred,
        DeskAction.unstar => !binned && starred,
        DeskAction.remove => !binned,
        DeskAction.restore => binned,
        DeskAction.deleteForever => binned,
      };
}

/// The menu behind a row's three dots.
///
/// It is the same panel as the sort menu at the same size on the same arrival,
/// with a glyph in the gutter where the sort menu puts a check, because the
/// two are one control answering two kinds of question. It grows out of its
/// top right corner, which is the corner the dots that opened it sit on.
class OverflowMenu extends StatelessWidget {
  const OverflowMenu({
    super.key,
    required this.t,
    required this.entry,
    required this.actions,
    required this.onAction,
    this.oozed = false,
  });

  /// 0 to 1 across the menu's arrival.
  final double t;

  final LibraryEntry entry;

  /// What this document can have done to it, decided by the desk, which is
  /// the one that knows whether it is starred or binned.
  final List<DeskAction> actions;

  final ValueChanged<DeskAction> onAction;

  /// True when a body of goo is growing into this panel's shape underneath it.
  ///
  /// The panel then does not scale, because the goo is already doing the
  /// growing and two things growing at once is one of them arriving late. It
  /// only hardens: the rows come up over the second half of the arrival, once
  /// the body they sit on has reached its full size.
  final bool oozed;

  @override
  Widget build(BuildContext context) {
    final eased = easeOutCubic.transform(t.clamp(0.0, 1.0));
    return Opacity(
      opacity: oozed ? ((eased - 0.45) / 0.55).clamp(0.0, 1.0) : eased,
      child: Transform.scale(
        scale: oozed ? 1 : lerpDouble(kSortMenuScaleFrom, 1, eased)!,
        alignment: Alignment.topRight,
        child: Container(
          width: kSortMenuWidth,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(kSortMenuRadius),
            border: AppEdges.all(context),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final action in actions)
                _ActionRow(action: action, onTap: () => onAction(action)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final DeskAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Removal is the one row here you cannot simply do again, so it is the one
    // row set in the accent. The undo pill is what makes it recoverable; the
    // colour is what makes it deliberate.
    final colour = action.destructive ? AppColors.accentBright : AppColors.ink;
    return PaperPress(
      onTap: onTap,
      semanticLabel: action.label,
      // Removal is the one row here that changes what is on the desk, so it
      // is the one row that does not feel like the others.
      feel: action.destructive ? Feel.commit : Feel.tap,
      child: SizedBox(
        height: kSortMenuRowHeight,
        child: Padding(
          padding: const EdgeInsets.only(
            left: kSortMenuPaddingLeft,
            right: kSortMenuPaddingRight,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: kOverflowMenuGutter,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    action.icon,
                    size: kOverflowMenuGlyph,
                    color: colour,
                  ),
                ),
              ),
              Text(
                action.label,
                style: AppText.menuRow.copyWith(color: colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
