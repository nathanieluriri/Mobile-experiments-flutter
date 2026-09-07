import 'package:flutter/widgets.dart';

/// A tap target that dims while it is held, the way a pressable does on the
/// phone. [heldOpacity] is the fraction it fades to.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.heldOpacity,
    required this.child,
    this.onTap,
  });

  final double heldOpacity;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _held = false;

  void _setHeld(bool held) {
    if (_held != held) {
      setState(() => _held = held);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setHeld(true),
      onTapUp: (_) => _setHeld(false),
      onTapCancel: () => _setHeld(false),
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: _held ? widget.heldOpacity : 1,
        child: widget.child,
      ),
    );
  }
}
