import 'package:flutter/widgets.dart';

/// Lets [child] be laid out at its natural size and spill past the box it was
/// given, the way a page element does when its container hides the overflow.
/// The nearest clip above does the cutting.
class Spill extends StatelessWidget {
  const Spill({
    super.key,
    this.horizontal = false,
    this.vertical = false,
    this.alignment = Alignment.topLeft,
    required this.child,
  });

  final bool horizontal;
  final bool vertical;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return OverflowBox(
      alignment: alignment,
      maxWidth: horizontal ? double.infinity : null,
      maxHeight: vertical ? double.infinity : null,
      child: child,
    );
  }
}
