import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Text that fades and slides when its content changes.
class FadeSwapText extends StatelessWidget {
  const FadeSwapText({
    super.key,
    required this.text,
    required this.style,
    this.alignment = Alignment.centerLeft,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Eases.iosOut,
      switchOutCurve: Curves.linear,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, (1 - animation.value) * 8),
                child: child,
              );
            },
          ),
        );
      },
      layoutBuilder: (current, previous) {
        return Stack(
          alignment: alignment,
          children: [...previous, ?current],
        );
      },
      child: Text(text, key: ValueKey(text), style: style, textAlign: textAlign),
    );
  }
}
