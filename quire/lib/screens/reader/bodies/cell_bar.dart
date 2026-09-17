import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';

/// Room at the right of the bar for the folio chip, which floats over the
/// sheet's bottom right corner and would otherwise sit on the bar's words.
const kCellBarChipClearance = kFolioChipWidth + 2 * kFolioChipInset;

/// What the chosen cell holds, in full, at the foot of the grid.
///
/// A column is never wide enough for the cell you care about, so the bar is
/// where a cell is read. It is shaped like a spreadsheet's own formula field,
/// a rounded well with `fx` at its head, because that is the shape a reader
/// already knows to look in. It shows the formula when the cell was worked out
/// by one and the value when it was typed, the address beside it, and, when
/// somebody has said something about the cell, what they said underneath.
class CellBar extends StatelessWidget {
  const CellBar({
    super.key,
    required this.reference,
    required this.value,
    required this.progress,
    this.formula,
    this.comment,
    this.commentBy,
    this.noteOpen,
  });

  /// `Runs!G3`: the sheet, the letter and the file's own row number.
  final String reference;

  final String value;

  /// The formula behind [value], when there is one.
  final String? formula;

  /// What somebody said about the cell, and who.
  final String? comment;
  final String? commentBy;

  /// 0 below the foot of the grid, 1 risen.
  final double progress;

  /// How much room the comment line has, from 0 to 1. The bar opens its room
  /// for a comment rather than jumping taller, and closes it the same way,
  /// when the choice moves between a cell somebody talked about and one
  /// nobody did. Left out, the room is all there when there is a comment and
  /// none when there is not.
  final double? noteOpen;

  /// How tall the bar is for a cell with and without a comment on it.
  static double heightFor({required bool commented}) =>
      kCellBarHeight + (commented ? kCellBarNoteHeight : 0);

  @override
  Widget build(BuildContext context) {
    final said = comment;
    final room = (noteOpen ?? (said == null ? 0.0 : 1.0)).clamp(0.0, 1.0);
    final height = kCellBarHeight + kCellBarNoteHeight * room;
    final worked = formula;
    return Transform.translate(
      offset: Offset(0, height * (1 - progress.clamp(0.0, 1.0))),
      child: Container(
        height: height,
        // Clear of the folio chip, which floats over the bar's right end.
        padding: const EdgeInsets.fromLTRB(
          kCellBarPadX,
          kCellBarPadY,
          kCellBarChipClearance,
          kCellBarPadY,
        ),
        decoration: const BoxDecoration(
          color: AppColors.ground,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The well takes what the note's room leaves, and the bar grows
            // by exactly that room, so the well itself never changes height.
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(kCellBarWellRadius),
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      'fx',
                      style: AppText.label.copyWith(
                        color: AppColors.inkFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          worked == null ? value : '=$worked',
                          style: (worked == null ? AppText.label : AppText.code)
                              .copyWith(color: AppColors.ink),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      reference,
                      style: AppText.folio.copyWith(
                        color: AppColors.accentBright,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
            if (said != null && room > 0)
              SizedBox(
                height: kCellBarNoteHeight * room,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: kCellBarNoteHeight,
                    maxHeight: kCellBarNoteHeight,
                    child: Opacity(opacity: room, child: _note(said)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _note(String said) => Padding(
    padding: const EdgeInsets.only(top: 8, left: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(LucideIcons.messageSquare, size: 15, color: AppColors.found),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <TextSpan>[
                if ((commentBy ?? '').isNotEmpty)
                  TextSpan(
                    text: '$commentBy  ',
                    style: AppText.label.copyWith(color: AppColors.ink),
                  ),
                TextSpan(
                  text: said,
                  style: AppText.label.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
            // A style of its own at the root, so the lines take nothing
            // from whatever text style happens to be above the bar.
            style: AppText.label.copyWith(color: AppColors.inkSoft),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
