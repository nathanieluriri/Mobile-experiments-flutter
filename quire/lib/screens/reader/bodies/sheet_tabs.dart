import 'package:flutter/widgets.dart';

import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/press_fade.dart';

/// The gap between two sheet tabs, and the inset of the first from the sheet's
/// left edge. On the spacing scale, and small enough that three named sheets
/// fit the phone without scrolling.
const kSheetTabGap = 8.0;

/// The row of tabs across the top of a workbook.
///
/// The active tab is [AppColors.leaf], which is the sheet's own colour, so it
/// reads as the page you are holding rather than as a selected button. The
/// others are [AppColors.panel]: paper still, but filed behind.
class SheetTabs extends StatelessWidget {
  const SheetTabs({
    super.key,
    required this.names,
    required this.active,
    this.onSelect,
  });

  final List<String> names;
  final int active;
  final void Function(int index)? onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSheetTabHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSheetTabGap),
        itemCount: names.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: kSheetTabGap),
        itemBuilder: (context, index) => _Tab(
          name: names[index],
          selected: index == active,
          onTap: onSelect == null ? null : () => onSelect!(index),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.name, required this.selected, this.onTap});

  final String name;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      shadow: false,
      borderRadius: BorderRadius.circular(kChipRadius),
      semanticLabel: name,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.leaf : AppColors.panel,
          borderRadius: BorderRadius.circular(kChipRadius),
          border: selected
              ? const Border(
                  bottom: BorderSide(
                    color: AppColors.thread,
                    width: kChipUnderlineHeight,
                  ),
                )
              : null,
        ),
        child: Text(
          name,
          style: AppText.label.copyWith(
            color: selected ? AppColors.ink : AppColors.inkSoft,
          ),
          maxLines: 1,
        ),
      ),
    );
  }
}
