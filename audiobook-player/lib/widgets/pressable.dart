import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/widgets.dart';

/// A tap target that dims the moment it is touched, the way a pressable does on
/// the phone, and stops dimming as soon as the touch turns into a scroll.
/// [heldOpacity] is the fraction it fades to.
///
/// Only the innermost pressable under the finger dims: a transport disc inside
/// a row dims the disc alone, not the row around it.
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
  bool _innerHeld = false;
  Offset _touchedAt = Offset.zero;
  _PressableState? _enclosing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enclosing = context.findAncestorStateOfType<_PressableState>();
  }

  bool get _dimmed => _held && !_innerHeld;

  void _setHeld(bool held) {
    if (_held != held) {
      setState(() => _held = held);
    }
    _enclosing?._setInnerHeld(held);
  }

  void _setInnerHeld(bool innerHeld) {
    if (_innerHeld != innerHeld) {
      setState(() => _innerHeld = innerHeld);
    }
    _enclosing?._setInnerHeld(innerHeld);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _touchedAt = event.position;
        _setHeld(true);
      },
      // Once the finger has travelled far enough to be a scroll, the press is
      // off, the same as letting go.
      onPointerMove: (event) {
        if ((event.position - _touchedAt).distance > kTouchSlop) {
          _setHeld(false);
        }
      },
      onPointerUp: (_) => _setHeld(false),
      onPointerCancel: (_) => _setHeld(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapCancel: () => _setHeld(false),
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: _dimmed ? widget.heldOpacity : 1,
          child: widget.child,
        ),
      ),
    );
  }
}
