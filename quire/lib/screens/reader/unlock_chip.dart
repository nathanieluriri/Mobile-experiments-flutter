import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/feedback.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// The chip's own measurements.
const kUnlockChipHeight = 40.0;
const kUnlockChipPadX = 16.0;
const kUnlockChipGap = 8.0;
const kUnlockChipGlyph = 17.0;
const kUnlockChipBottom = 28.0;

/// How far the chip rises as it arrives.
const kUnlockChipRise = 10.0;

/// How long it waits before going again.
const kUnlockChipHold = Duration(seconds: 3);
const kUnlockChipFade = Duration(milliseconds: 220);

/// The one control a locked page has: a chip that comes up on a tap and goes
/// again on its own.
///
/// A page lock takes every bar off the screen, which is the point of it, so
/// something has to be the way back. It is summoned rather than standing
/// there, because a padlock parked in the corner of a page you asked to see
/// clean is the app writing on the document.
///
/// It says what it will do rather than only showing a glyph. A control that
/// appears for three seconds over somebody's reading has one chance to be
/// understood.
class UnlockChip extends StatelessWidget {
  const UnlockChip({
    super.key,
    required this.progress,
    required this.onUnlock,
    this.label = 'Unlock the page',
  });

  /// 0 with the chip gone, 1 with it fully up.
  final double progress;

  final VoidCallback onUnlock;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom:
          MediaQuery.paddingOf(context).bottom +
          kUnlockChipBottom +
          kUnlockChipRise * t -
          kUnlockChipRise,
      child: Center(
        child: Opacity(
          opacity: t,
          child: PaperPress(
            onTap: onUnlock,
            semanticLabel: label,
            feel: Feel.commit,
            washRadius: kUnlockChipHeight / 2,
            child: Container(
              height: kUnlockChipHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: kUnlockChipPadX,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(kUnlockChipHeight / 2),
                border: AppEdges.all(context),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.lockKeyholeOpen,
                    size: kUnlockChipGlyph,
                    color: AppColors.accentBright,
                  ),
                  const SizedBox(width: kUnlockChipGap),
                  Text(
                    label,
                    style: AppText.actionPill.copyWith(color: AppColors.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the reader is told the moment a lock goes on.
///
/// A lock that takes the bars away without a word is indistinguishable from a
/// crash, so the page says what happened and how to undo it, once, and then
/// leaves the reading alone.
const kPageLockNotice = 'Locked to this page. Tap the page to unlock.';
const kBackLockNotice = 'Locked. Tap the padlock to leave.';

/// How wide the notice sits, and how long it stays.
const kLockNoticeWidth = 300.0;
const kLockNoticeHold = Duration(seconds: 3);
