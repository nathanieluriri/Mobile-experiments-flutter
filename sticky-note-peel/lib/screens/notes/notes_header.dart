import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';

/// Menu and search either side of the title that fades in as the list scrolls
/// under it.
class NotesHeader extends StatelessWidget {
  const NotesHeader({super.key, required this.scrollY, required this.dim});

  final double scrollY;

  /// 0 when nothing is lifted, 1 when a note is.
  final double dim;

  @override
  Widget build(BuildContext context) {
    final t = rangeProgress(scrollY, kSmallTitleRange);
    return Opacity(
      opacity: 1 - kChromeDimAmount * dim,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kHeaderHorizontalPadding,
          vertical: kHeaderVerticalPadding,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, kTitleShift * (1 - t)),
                child: const Text(
                  kNotesScreenTitle,
                  style: TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeights.semiBold,
                    fontSize: 16,
                    height: kLineHeight,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: kHeaderButtonSize,
                  height: kHeaderButtonSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(kHeaderButtonRadius),
                  ),
                  child: const Icon(
                    LucideIcons.menu,
                    size: 18,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(
                  width: kHeaderButtonSize,
                  height: kHeaderButtonSize,
                  child: Center(
                    child: Icon(
                      LucideIcons.search,
                      size: 21,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
