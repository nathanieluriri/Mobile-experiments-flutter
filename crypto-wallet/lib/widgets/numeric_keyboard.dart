import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/theme.dart';
import 'haptics.dart';

/// The delete key's label.
const String kDeleteKey = 'del';

const List<List<String>> _rows = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['.', '0', kDeleteKey],
];

/// A four-row keypad for amounts.
class NumericKeyboard extends StatelessWidget {
  const NumericKeyboard({super.key, required this.onKey, this.onClearAll});

  final ValueChanged<String> onKey;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < _rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 4),
            Row(
              children: [
                for (var c = 0; c < _rows[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: 4),
                  Expanded(
                    child: KeypadKeyButton(
                      label: _rows[r][c],
                      onKey: onKey,
                      onClearAll: onClearAll,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One key: shrinks on press with a soft ink ripple behind it.
class KeypadKeyButton extends StatefulWidget {
  const KeypadKeyButton({
    super.key,
    required this.label,
    required this.onKey,
    this.onClearAll,
  });

  final String label;
  final ValueChanged<String> onKey;
  final VoidCallback? onClearAll;

  @override
  State<KeypadKeyButton> createState() => _KeypadKeyButtonState();
}

class _KeypadKeyButtonState extends State<KeypadKeyButton>
    with TickerProviderStateMixin {
  late final AnimationController _pressed = AnimationController.unbounded(vsync: this);
  late final AnimationController _rippleScale =
      AnimationController.unbounded(vsync: this, value: 0.6);
  late final AnimationController _rippleOpacity = AnimationController(vsync: this);

  bool get _isDelete => widget.label == kDeleteKey;

  void _down(TapDownDetails details) {
    _pressed.animateWith(springTo(Springs.press, _pressed.value, 1));
    _rippleScale.value = 0.6;
    _rippleScale.animateWith(springTo(Springs.pop, 0.6, 1));
    _rippleOpacity.animateTo(1, duration: const Duration(milliseconds: 80));
    if (_isDelete) {
      Haptics.press();
    } else {
      Haptics.tap();
    }
  }

  void _up() {
    _pressed.animateWith(springTo(Springs.press, _pressed.value, 0));
    _rippleOpacity.animateTo(0, duration: const Duration(milliseconds: 280));
  }

  @override
  void dispose() {
    _pressed.dispose();
    _rippleScale.dispose();
    _rippleOpacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: () => widget.onKey(widget.label),
      onLongPress: _isDelete ? widget.onClearAll : null,
      child: SizedBox(
        height: 56,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pressed, _rippleScale, _rippleOpacity]),
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: _rippleScale.value,
                  child: Container(
                    width: 68,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.06 * _rippleOpacity.value),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 1 - _pressed.value * 0.06,
                  child: _isDelete
                      ? const Icon(LucideIcons.delete, size: 23, color: AppColors.ink)
                      : Text(widget.label, style: text(26, weight: FontWeight.w600)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
