import 'package:flutter/widgets.dart';

import '../../../theme/colors.dart';
import '../../../theme/edges.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';

/// How much of the bar's right end is left empty.
///
/// The folio chip floats in the sheet's bottom right corner, which is exactly
/// where the formula wants to sit. The bar runs the full width of the sheet,
/// because a bar that stopped short would read as a card, but its text keeps
/// clear of the chip rather than printing a formula nobody can read.
const kCellBarChipClearance = kFolioChipWidth + 2 * kFolioChipInset;

/// The forty point bar that rises from the sheet's bottom edge to read a cell.
///
/// It exists so a truncated cell can be read without the column widening: a
/// grid that reflows under the finger that touched it is the failure every
/// phone spreadsheet viewer makes, and the reason none of them can be scanned.
class CellBar extends StatelessWidget {
  const CellBar({
    super.key,
    required this.reference,
    required this.value,
    required this.progress,
    this.formula,
  });

  /// `Runs!G3`, the cell's own name.
  final String reference;

  /// The full value, untruncated, however wide it is.
  final String value;

  /// The cached formula the value came from, or null.
  final String? formula;

  /// How far the bar has risen, 0 at the sheet's edge and 1 fully up.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final showing = formula;
    return Transform.translate(
      offset: Offset(0, kCellBarHeight * (1 - progress.clamp(0.0, 1.0))),
      child: Container(
        height: kCellBarHeight,
        padding: const EdgeInsets.only(
          left: 12,
          right: kCellBarChipClearance,
        ),
        // One rule along the top edge, and an opaque control fill under it.
        // The bar covers the last row of the grid, and the grid stripes
        // between the sheet and the leaf, so the fill has to stand above both
        // or the covered row reads as a row that has merely gone blank. Its
        // three free edges are the sheet's, so the top rule is the whole ring
        // this shape needs.
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          border: Border(top: AppEdges.side(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              reference,
              style: AppText.folio.copyWith(color: AppColors.accentBright),
              maxLines: 1,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  value,
                  style: AppText.label.copyWith(color: AppColors.ink),
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
            if (showing != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  showing,
                  style: AppText.code.copyWith(color: AppColors.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
