import 'package:flutter/widgets.dart';

/// A tappable thing that dims while a finger is on it and comes back when the
/// finger leaves, the way the chrome buttons on this screen have always looked
/// as though they should.
class PressFade extends StatefulWidget {
  const PressFade({
    super.key,
    required this.onTap,
    required this.child,
    this.activeOpacity = 0.2,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final Widget child;

  /// How far down the opacity goes while pressed.
  final double activeOpacity;

  final String? semanticLabel;

  @override
  State<PressFade> createState() => _PressFadeState();
}

class _PressFadeState extends State<PressFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    reverseDuration: const Duration(milliseconds: 250),
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press.forward(),
        onTapUp: (_) => _press.reverse(),
        onTapCancel: () => _press.reverse(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) => Opacity(
            opacity: 1 - (1 - widget.activeOpacity) * _press.value,
            child: child,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
