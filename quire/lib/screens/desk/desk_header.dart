import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import 'desk_search_field.dart';

/// How opaque the bar the wordmark collapses into is.
const kDeskBarFill = 0.92;

/// The line box each wordmark sets in, so both centre in the same band.
const kWordmarkBox = 34.0;
const kWordmarkSmallBox = 22.0;

/// How much of [kSearchOpen] the wordmark takes to cross fade out.
///
/// It leaves before the field has finished arriving, so the two are never both
/// asking to be read.
const kWordmarkFadeMs = 120;

/// The desk's head: the word `quire`, and the one control on the screen.
///
/// The large wordmark and the small one are the same word at two sizes, and
/// the scroll offset decides which of them you are looking at. Nothing else
/// lives here: no tabs, no sort, no overflow menu.
class DeskHeader extends StatelessWidget {
  const DeskHeader({
    super.key,
    required this.scrollY,
    required this.searchOpen,
    required this.searchRaw,
    required this.dim,
    required this.field,
  });

  /// Where the list has been scrolled to.
  final double scrollY;

  /// 0 to 1 across the search field's arrival, on its own curve.
  final double searchOpen;

  /// The same arrival before the curve, so the wordmark can leave on the first
  /// 120 of the 220 milliseconds rather than on a share of the easing.
  final double searchRaw;

  /// 0 when nothing is lifted, 1 when a card is.
  final double dim;

  final DeskSearchField field;

  @override
  Widget build(BuildContext context) {
    final small = rangeProgress(scrollY, kSmallTitleRange);
    final large = rangeProgress(scrollY, kLargeTitleRange);
    final overscroll = rangeProgress(scrollY, kOverscrollRange);
    final wordmarkOut =
        (searchRaw * kSearchOpen.inMilliseconds / kWordmarkFadeMs)
            .clamp(0.0, 1.0);
    final width = kHeaderButtonSize +
        (kScreenWidth - kScreenPadding * 2 - kHeaderButtonSize) * searchOpen;

    return Opacity(
      opacity: 1 - kChromeDimAmount * dim,
      child: SizedBox(
        height: kDeskHeaderTop + kDeskHeaderHeight,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: kDeskHeaderTop,
              height: kDeskHeaderHeight,
              child: Opacity(
                opacity: small,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.leaf.withValues(alpha: kDeskBarFill),
                    border: const Border(
                      bottom: BorderSide(color: AppColors.rule, width: 1),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: kScreenPadding,
              top: kDeskHeaderTop + (kDeskHeaderHeight - kWordmarkBox) / 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (1 - large) * (1 - wordmarkOut),
                  child: Transform.scale(
                    scale:
                        kOverscrollScale + (1 - kOverscrollScale) * overscroll,
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: Offset(0, -kTitleShift * large),
                      child: Text(
                        'quire',
                        style: AppText.wordmark.copyWith(color: AppColors.ink),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: kScreenPadding,
              top: kDeskHeaderTop + (kDeskHeaderHeight - kWordmarkSmallBox) / 2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: small * (1 - wordmarkOut),
                  child: Transform.translate(
                    offset: Offset(0, kTitleShift * (1 - small)),
                    child: Text(
                      'quire',
                      style:
                          AppText.wordmarkSmall.copyWith(color: AppColors.ink),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: kScreenPadding,
              top: kDeskHeaderTop + (kDeskHeaderHeight - kHeaderButtonSize) / 2,
              width: width,
              child: field,
            ),
          ],
        ),
      ),
    );
  }
}
