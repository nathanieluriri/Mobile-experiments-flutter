import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/colors.dart';
import '../../theme/easings.dart';
import '../../theme/metrics.dart';
import '../../widgets/press_fade.dart';

/// Something the plus button can add to a note.
enum ComposeAction {
  /// A line of prose.
  text(LucideIcons.type, 'Write'),

  /// One more thing to tick off.
  todo(LucideIcons.listTodo, 'Add a to-do'),

  /// Which list the note belongs to.
  tag(LucideIcons.tag, 'Put it in a list'),

  /// What the paper is made of.
  paper(LucideIcons.palette, 'Change the paper');

  const ComposeAction(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The plus that opens into a row of things you can add, and closes again as a
/// cross.
///
/// The circles are the dock's circles, drawn in ink on paper instead of paper
/// on ink, and they arrive one after another the same way.
class ComposeActionBar extends StatelessWidget {
  const ComposeActionBar({
    super.key,
    required this.open,
    required this.onToggle,
    required this.onAction,
  });

  /// 0 with only the plus showing, 1 with every action out.
  final double open;

  final VoidCallback onToggle;
  final ValueChanged<ComposeAction> onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kComposeActionSize,
      child: Row(
        children: [
          Transform.rotate(
            angle: open * 0.7853981633974483,
            child: _circle(
              icon: LucideIcons.plus,
              label: open > 0.5 ? 'Close' : 'Add to this note',
              onTap: onToggle,
              outlined: false,
            ),
          ),
          for (final (index, action) in ComposeAction.values.indexed) ...[
            SizedBox(width: kComposeActionGap * _reveal(index)),
            _revealed(index, action),
          ],
        ],
      ),
    );
  }

  /// Each circle waits its turn, so the row unrolls rather than appearing.
  double _reveal(int index) {
    const total = 1.0;
    final start = index * 0.12;
    final span = total - ComposeAction.values.length * 0.12 + 0.12;
    return Interval(start, start + span, curve: easeOutCubic).transform(open);
  }

  Widget _revealed(int index, ComposeAction action) {
    final t = _reveal(index);
    if (t <= 0) {
      return const SizedBox.shrink();
    }
    return Opacity(
      opacity: t,
      child: Align(
        widthFactor: t,
        child: Transform.scale(
          scale: 0.6 + 0.4 * t,
          child: _circle(
            icon: action.icon,
            label: action.label,
            onTap: () => onAction(action),
            outlined: true,
          ),
        ),
      ),
    );
  }

  Widget _circle({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool outlined,
  }) {
    return PressFade(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: kComposeActionSize,
        height: kComposeActionSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.noteText.withValues(alpha: outlined ? 0.55 : 0.35),
            width: 1.2,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: AppColors.noteText.withValues(alpha: outlined ? 0.85 : 0.6),
        ),
      ),
    );
  }
}
