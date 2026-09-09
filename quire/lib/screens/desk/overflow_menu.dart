import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/library.dart';
import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// Everything a document can have done to it that is not reading it.
enum DeskAction {
  read(label: 'Open', icon: LucideIcons.bookOpen),
  sign(label: 'Sign', icon: LucideIcons.penLine),
  dogEar(label: 'Dog ear', icon: LucideIcons.bookmark),
  remove(label: 'Remove', icon: LucideIcons.trash2);

  const DeskAction({required this.label, required this.icon});

  final String label;
  final IconData icon;

  /// True when this action means anything for [entry].
  ///
  /// Only a PDF carries a signature, so offering to sign a spreadsheet would
  /// be offering something the app would then have to refuse.
  bool suits(LibraryEntry entry) =>
      this != DeskAction.sign || entry.format == DocFormat.pdf;
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
    required this.onAction,
  });

  /// 0 to 1 across the menu's arrival.
  final double t;

  final LibraryEntry entry;
  final ValueChanged<DeskAction> onAction;

  /// What this document can actually have done to it.
  List<DeskAction> get actions =>
      DeskAction.values.where((action) => action.suits(entry)).toList();

  @override
  Widget build(BuildContext context) {
    final eased = easeOutCubic.transform(t.clamp(0.0, 1.0));
    return Opacity(
      opacity: eased,
      child: Transform.scale(
        scale: lerpDouble(kSortMenuScaleFrom, 1, eased)!,
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
    final colour =
        action == DeskAction.remove ? AppColors.accentBright : AppColors.ink;
    return PaperPress(
      onTap: onTap,
      semanticLabel: action.label,
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
