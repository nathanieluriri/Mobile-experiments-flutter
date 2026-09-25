import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'shell_model.dart';

/// The sort menu: four things to order by, and which way round.
///
/// It grows out of its own top left corner, which is the corner nearest the
/// label that opened it, so the menu reads as that label unfolding rather than
/// as a panel arriving from nowhere. Exactly one row in each group carries a
/// check, because the two groups are two questions and neither has an answer
/// of none.
class SortMenu extends StatelessWidget {
  const SortMenu({
    super.key,
    required this.t,
    required this.field,
    required this.order,
    required this.onField,
    required this.onOrder,
  });

  /// 0 to 1 across the menu's arrival.
  final double t;

  final SortField field;
  final SortOrder order;
  final ValueChanged<SortField> onField;
  final ValueChanged<SortOrder> onOrder;

  @override
  Widget build(BuildContext context) {
    final eased = easeOutCubic.transform(t.clamp(0.0, 1.0));
    return Opacity(
      opacity: eased,
      child: Transform.scale(
        scale: lerpDouble(kSortMenuScaleFrom, 1, eased)!,
        alignment: Alignment.topLeft,
        child: Container(
          width: kSortMenuWidth,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(kSortMenuRadius),
            border: AppEdges.all(context),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            // Stretched so the divider between the two groups is the menu's
            // full width. A centred column would give a rule with no width to
            // be, and the two questions would run together.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final value in SortField.values)
                _MenuRow(
                  label: value.label,
                  checked: value == field,
                  onTap: () => onField(value),
                ),
              SizedBox(
                height: hairline(context),
                child: const ColoredBox(color: AppColors.hairline),
              ),
              for (final value in SortOrder.values)
                _MenuRow(
                  label: value.label,
                  checked: value == order,
                  onTap: () => onOrder(value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        height: kSortMenuRowHeight,
        child: Padding(
          padding: const EdgeInsets.only(
            left: kSortMenuPaddingLeft,
            right: kSortMenuPaddingRight,
          ),
          child: Row(
            children: [
              // The gutter is held open on every row, checked or not, so the
              // labels make one column and the eye only has to scan the marks.
              SizedBox(
                width: kSortMenuGutter,
                child: checked
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(
                          LucideIcons.check,
                          size: kSortMenuCheck,
                          color: AppColors.ink,
                        ),
                      )
                    : null,
              ),
              Text(
                label,
                style: (checked ? AppText.menuRowSelected : AppText.menuRow)
                    .copyWith(color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
