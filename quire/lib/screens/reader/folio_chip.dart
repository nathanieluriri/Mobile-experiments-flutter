import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/digit_roll.dart';

/// How wide the dog ear tick on the chip is drawn.
const kFolioTick = 3.0;

/// How far the chip drops when the chrome leaves.
const kFolioChipHidden = 64.0;

/// Where the reader is, printed on a pill that floats over the sheet's bottom
/// right corner.
///
/// The number rolls rather than jumps, because a page count that flickers
/// while a thumb is on the fore edge is the difference between scrubbing a
/// document and guessing at one.
class FolioChip extends StatelessWidget {
  const FolioChip({
    super.key,
    required this.label,
    this.hidden = 0,
    this.dogEared = false,
    this.tint = 0,
  });

  /// What the chip reads: `4 / 6`, `24 / 73`, `38%`.
  final String label;

  /// 0 with the chrome in, 1 with it gone.
  final double hidden;

  /// True when the page showing has its corner turned, which lights the tick.
  final bool dogEared;

  /// How far the fill has travelled from the sheet toward the accent, 0 to 1.
  /// It runs with a scrub past a dog ear nub and sits at 0 the rest of the
  /// time.
  final double tint;

  @override
  Widget build(BuildContext context) {
    // Opaque at both ends of the tint. The chip lands squarely on body text,
    // and a number you can read the page through is the one thing here that
    // would look like a bug rather than like a chip.
    //
    // It rests at [AppColors.surfaceHigh] rather than the sheet's own value,
    // because it sits on the sheet, on the back of the sheet, and on a white
    // rendered page, and only a control value stands above all three.
    final fill = Color.lerp(
      AppColors.surfaceHigh,
      AppColors.accent,
      tint.clamp(0, 1),
    )!;
    final ink = Color.lerp(
      AppColors.ink,
      AppColors.onAccent,
      tint.clamp(0, 1),
    )!;
    return Opacity(
      opacity: 1 - hidden,
      child: Container(
        height: kFolioChipHeight,
        constraints: const BoxConstraints(minWidth: kFolioChipWidth),
        padding: const EdgeInsets.symmetric(horizontal: kSpace12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(kPillRadius),
          border: AppEdges.all(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (dogEared)
              Padding(
                padding: const EdgeInsets.only(right: kSpace4),
                child: Container(
                  width: kFolioTick,
                  height: kFolioTick,
                  decoration: const BoxDecoration(
                    color: AppColors.accentBright,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            DigitRoll(label, style: AppText.folio, color: ink),
          ],
        ),
      ),
    );
  }
}
