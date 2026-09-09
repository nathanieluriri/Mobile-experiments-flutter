import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/digit_roll.dart';
import '../../widgets/press_fade.dart';
import 'shell_model.dart';

/// The five format tabs, each carrying how much it holds.
///
/// The count is part of the tab rather than a badge on it, because the number
/// is what you are choosing between: DOCS with a 1 beside it tells you not to
/// bother before you have tapped it. It rolls rather than cuts, so a document
/// leaving the library moves one digit instead of repainting the row.
class TabStrip extends StatelessWidget {
  const TabStrip({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final DeskTab selected;

  /// How many documents each tab holds, before the search is applied.
  final Map<DeskTab, int> counts;

  final ValueChanged<DeskTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kTabStripHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kTabStripPaddingX),
        child: Row(
          children: [
            for (final tab in DeskTab.values) ...[
              if (tab != DeskTab.values.first) const SizedBox(width: kTabGap),
              _Tab(
                tab: tab,
                selected: tab == selected,
                count: counts[tab] ?? 0,
                onSelect: onSelect,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.count,
    required this.onSelect,
  });

  final DeskTab tab;
  final bool selected;
  final int count;
  final ValueChanged<DeskTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: () => onSelect(tab),
      semanticLabel: '${tab.label} $count',
      child: Container(
        height: kTabPillHeight,
        padding: const EdgeInsets.symmetric(horizontal: kTabPillPaddingX),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentMuted : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(kTabPillRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tab.label,
              style: AppText.label.copyWith(
                color: selected ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: kTabCountGap),
            DigitRoll(
              '$count',
              style: AppText.cell,
              color: AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}
