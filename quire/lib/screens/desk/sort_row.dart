import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';
import 'shell_model.dart';

/// Between the sort label and the circle that says which way it runs.
const kSortLabelGap = 8.0;
const kSortArrowGlyph = 14.0;
const kViewToggleGlyph = 18.0;

/// The row under the tabs: what the list is ordered by on the left, and how it
/// is laid out on the right.
///
/// The arrow turns over rather than swapping for a second glyph. It is the
/// same arrow either way up, and watching it go over is what tells you the
/// list you are looking at is the one you were looking at, reversed.
class SortRow extends StatefulWidget {
  const SortRow({
    super.key,
    required this.field,
    required this.order,
    required this.view,
    required this.onOpenMenu,
    required this.onView,
    this.anchorKey,
  });

  final SortField field;
  final SortOrder order;
  final DeskView view;

  /// Both the label and the arrow open the menu, because they are one
  /// statement about one thing.
  final VoidCallback onOpenMenu;

  final ValueChanged<DeskView> onView;

  /// Put on the label so the menu can be hung off exactly where it is.
  final Key? anchorKey;

  @override
  State<SortRow> createState() => _SortRowState();
}

class _SortRowState extends State<SortRow> with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: kSortArrowFlip,
    value: widget.order == SortOrder.newToOld ? 0 : 1,
  );

  @override
  void didUpdateWidget(SortRow old) {
    super.didUpdateWidget(old);
    if (old.order == widget.order) return;
    if (widget.order == SortOrder.newToOld) {
      _flip.reverse();
    } else {
      _flip.forward();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSortRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSortRowPaddingX),
        child: Row(
          children: [
            PaperPress(
              onTap: widget.onOpenMenu,
              semanticLabel: 'Sort by ${widget.field.label}',
              child: Row(
                key: widget.anchorKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.field.label,
                    style: AppText.sortLabel.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(width: kSortLabelGap),
                  AnimatedBuilder(
                    animation: _flip,
                    builder: (context, child) => Transform.rotate(
                      angle: math.pi * easeInOutQuad.transform(_flip.value),
                      child: child,
                    ),
                    child: Container(
                      width: kSortArrowCircle,
                      height: kSortArrowCircle,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.arrowDown,
                        size: kSortArrowGlyph,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _ViewToggle(
              icon: LucideIcons.list,
              label: 'List',
              selected: widget.view == DeskView.list,
              onTap: () => widget.onView(DeskView.list),
            ),
            const SizedBox(width: kViewToggleGap),
            _ViewToggle(
              icon: LucideIcons.layoutGrid,
              label: 'Grid',
              selected: widget.view == DeskView.grid,
              onTap: () => widget.onView(DeskView.grid),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the two layouts. The selected one fills; the other is only its
/// glyph, so the pair reads as one switch rather than as two buttons.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PaperPress(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: kViewToggleWidth,
        height: kViewToggleHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentPale : null,
          borderRadius: BorderRadius.circular(kViewToggleRadius),
        ),
        child: Icon(
          icon,
          size: kViewToggleGlyph,
          color: selected ? AppColors.onAccentBright : AppColors.inkSoft,
        ),
      ),
    );
  }
}
