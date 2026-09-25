import 'package:flutter/widgets.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../widgets/press_fade.dart';

/// How tall the dark bar of actions over a selection is.
const double kActionPillHeight = 44.0;

/// The gap between that bar and the thing it acts on.
const double kActionPillGap = 10.0;

/// One thing the bar offers.
class PillAction {
  const PillAction(this.label, this.onTap, {this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

/// The dark rounded bar of words that comes up over whatever is selected,
/// the way the phone's own editors offer cut, copy, paste and delete.
class ActionPill extends StatelessWidget {
  const ActionPill({super.key, required this.actions});

  final List<PillAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kActionPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kActionPillHeight / 2),
        border: Border.all(color: AppColors.hairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final action in actions)
              PaperPress(
                onTap: action.onTap,
                semanticLabel: action.label,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: kActionPillHeight,
                    child: Center(
                      child: action.icon == null
                          ? Text(
                              action.label,
                              style: AppText.menuRow.copyWith(
                                color: AppColors.ink,
                              ),
                            )
                          : Icon(action.icon, size: 20, color: AppColors.ink),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Places the bar for a selection at [target]: above it when there is
/// space, below it when there is not, and never past either side.
class PillPlacement extends SingleChildLayoutDelegate {
  PillPlacement(this.target);

  final Rect target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final child = childSize;
    var top = target.top - kActionPillGap - child.height;
    if (top < 0) top = target.bottom + kActionPillGap;
    if (top + child.height > size.height) {
      top = (size.height - child.height).clamp(0, double.infinity).toDouble();
    }
    var left = target.center.dx - child.width / 2;
    if (left + child.width > size.width) left = size.width - child.width;
    if (left < 0) left = 0;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(PillPlacement oldDelegate) =>
      oldDelegate.target != target;
}
