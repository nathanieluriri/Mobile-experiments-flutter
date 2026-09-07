import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'haptics.dart';
import 'pressable_scale.dart';

/// The full-width call to action that fills with the accent when enabled.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.enabled,
    required this.onPress,
    this.label = 'Continue',
  });

  final bool enabled;
  final VoidCallback onPress;
  final String label;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController.unbounded(
    vsync: this,
    value: widget.enabled ? 1 : 0,
  );

  @override
  void didUpdateWidget(PrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _progress.animateWith(
        springTo(Springs.pop, _progress.value, widget.enabled ? 1 : 0),
      );
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scaleTo: 0.97,
      haptic: HapticKind.press,
      enabled: widget.enabled,
      onPress: widget.onPress,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final p = _progress.value;
          final t = p.clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 + p * 0.02,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.lerp(AppColors.disabled, AppColors.accent, t),
                borderRadius: BorderRadius.circular(27),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4 * t),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                widget.label,
                style: text(
                  17,
                  weight: FontWeight.w700,
                  color: Color.lerp(AppColors.subtle, AppColors.white, t)!,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
