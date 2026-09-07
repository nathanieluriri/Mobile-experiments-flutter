import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'haptics.dart';

/// A tappable surface that shrinks to [scaleTo] on a press spring and can
/// lift with a soft shadow.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPress,
    this.onLongPress,
    this.scaleTo = 0.97,
    this.haptic = HapticKind.tap,
    this.enabled = true,
    this.lift = false,
    this.liftRadius = 24,
  });

  final Widget child;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final double scaleTo;
  final HapticKind haptic;
  final bool enabled;
  final bool lift;
  final double liftRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressed = AnimationController.unbounded(vsync: this);

  void _down(TapDownDetails details) {
    if (!widget.enabled) {
      return;
    }
    _pressed.animateWith(springTo(Springs.press, _pressed.value, 1));
    Haptics.fire(widget.haptic);
  }

  void _release() {
    if (!widget.enabled) {
      return;
    }
    _pressed.animateWith(springTo(Springs.press, _pressed.value, 0));
  }

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.enabled ? widget.onPress : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedBuilder(
        animation: _pressed,
        child: widget.child,
        builder: (context, child) {
          final p = _pressed.value;
          Widget result = child!;
          if (widget.lift) {
            result = DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.liftRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.ink.withValues(alpha: 0.05 + p * 0.06),
                    blurRadius: 12 + p * 6,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: result,
            );
          }
          return Transform.scale(
            scale: 1 - (1 - widget.scaleTo) * p,
            child: result,
          );
        },
      ),
    );
  }
}
