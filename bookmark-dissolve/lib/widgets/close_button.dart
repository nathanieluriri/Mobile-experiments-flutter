import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/index.dart';

/// The cross in the top right corner of a bookmark card. Two rounded bars
/// crossed at right angles, dimmed while it is held.
class CardCloseButton extends StatefulWidget {
  const CardCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<CardCloseButton> createState() => _CardCloseButtonState();
}

class _CardCloseButtonState extends State<CardCloseButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      // The bar is 15 by 15; the target fills the title bar's height so it is
      // comfortable to hit without changing the layout around it.
      child: SizedBox(
        width: 15,
        height: 40,
        child: Center(
          child: Opacity(
            opacity: _pressed ? 0.35 : 1,
            child: const SizedBox(
              width: 15,
              height: 15,
              child: Stack(
                alignment: Alignment.center,
                children: [_Bar(math.pi / 4), _Bar(-math.pi / 4)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.angle);

  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 15,
        height: 1.5,
        decoration: BoxDecoration(
          color: AppColors.closeIcon,
          borderRadius: BorderRadius.circular(0.75),
        ),
      ),
    );
  }
}
