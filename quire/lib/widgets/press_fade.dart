import 'package:flutter/widgets.dart';

import '../theme/easings.dart';
import '../theme/metrics.dart';

/// How far a pressed object scales down about its own centre.
const kPressScale = 0.985;

/// How long a press takes to come back up. Slower than it goes down, because a
/// finger lifting is slower than a finger landing.
const kPressRelease = Duration(milliseconds: 120);

/// Every tappable object in the app presses the same way: it scales to
/// [kPressScale] about its own centre. Nothing changes colour and nothing
/// moves but the object itself.
///
/// Paper does not highlight, it presses against the desk. Applying one 90 ms
/// rule to forty unrelated controls is what makes them feel like one
/// manufactured object.
class PaperPress extends StatefulWidget {
  const PaperPress({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// A disabled object still lays out and still draws; it just does not press.
  final bool enabled;

  final String? semanticLabel;

  @override
  State<PaperPress> createState() => _PaperPressState();
}

class _PaperPressState extends State<PaperPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: kPress,
    reverseDuration: kPressRelease,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (widget.enabled) {
      _press.forward();
    }
  }

  void _up() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: AnimatedBuilder(
          animation: _press,
          builder: (context, child) {
            final t = easeOutQuad.transform(_press.value);
            return Transform.scale(
              scale: 1 - (1 - kPressScale) * t,
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
