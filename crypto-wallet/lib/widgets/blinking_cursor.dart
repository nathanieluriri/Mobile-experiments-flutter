import 'package:flutter/material.dart';

import '../theme/theme.dart';

const Duration _half = Duration(milliseconds: 460);

/// A thin accent bar that breathes between full and faint.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, required this.height});

  final double height;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: _half,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        final opacity = 1 - 0.92 * Eases.iosInOut.transform(_blink.value);
        return Container(
          width: 3,
          height: widget.height,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}
