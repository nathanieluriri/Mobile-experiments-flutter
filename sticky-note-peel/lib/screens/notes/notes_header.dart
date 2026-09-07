import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'search_field.dart';

/// Menu and search either side of the title that fades in as the list scrolls
/// under it.
class NotesHeader extends StatelessWidget {
  const NotesHeader({
    super.key,
    required this.scrollY,
    required this.dim,
    required this.title,
    required this.onMenu,
    required this.search,
  });

  final double scrollY;

  /// 0 when nothing is lifted, 1 when a note is.
  final double dim;

  /// What the list is showing, echoed here once it has scrolled away.
  final String title;

  final VoidCallback onMenu;

  /// The magnifier, and the field it grows into.
  final SearchField search;

  @override
  Widget build(BuildContext context) {
    final t = rangeProgress(scrollY, kSmallTitleRange) * (1 - search.open);
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
            IgnorePointer(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, kTitleShift * (1 - t)),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kFontFamily,
                      fontWeight: FontWeights.semiBold,
                      fontSize: 16,
                      height: kLineHeight,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ),
            // The menu steps aside as the field reaches across for its room.
            Align(
              alignment: Alignment.centerLeft,
              child: IgnorePointer(
                ignoring: search.open > 0.5,
                child: Opacity(
                  opacity: (1 - search.open * 2).clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(-kHeaderButtonSize * search.open, 0),
                    child: PressFade(
                      onTap: onMenu,
                      semanticLabel: 'Lists',
                      child: Container(
                        width: kHeaderButtonSize,
                        height: kHeaderButtonSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(kHeaderButtonRadius),
                        ),
                        child: const Icon(
                          LucideIcons.menu,
                          size: 18,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: kHeaderButtonSize +
                      (constraints.maxWidth - kHeaderButtonSize) * search.open,
                  child: search,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
