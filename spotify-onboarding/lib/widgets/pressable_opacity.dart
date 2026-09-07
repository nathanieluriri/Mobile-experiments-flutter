import 'package:flutter/widgets.dart';

/// A tap target that dims while it is held, the way the flow's buttons do.
class PressableOpacity extends StatefulWidget {
  const PressableOpacity({
    super.key,
    required this.child,
    required this.pressedOpacity,
    this.onTap,
  });

  final Widget child;
  final double pressedOpacity;
  final VoidCallback? onTap;

  @override
  State<PressableOpacity> createState() => _PressableOpacityState();
}

class _PressableOpacityState extends State<PressableOpacity> {
  bool _held = false;

  void _setHeld(bool value) {
    if (_held != value) {
      setState(() => _held = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setHeld(true),
      onTapUp: (_) => _setHeld(false),
      onTapCancel: () => _setHeld(false),
      child: Opacity(
        opacity: _held ? widget.pressedOpacity : 1,
        child: widget.child,
      ),
    );
  }
}
