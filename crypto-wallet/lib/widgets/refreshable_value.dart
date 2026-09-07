import 'package:flutter/material.dart';

import 'shimmer.dart';

/// Dims its child and shows a shimmer while a value is being recomputed.
class RefreshableValue extends StatefulWidget {
  const RefreshableValue({
    super.key,
    required this.refreshing,
    required this.child,
    this.shimmerWidth = 72,
    this.shimmerHeight = 16,
  });

  final bool refreshing;
  final Widget child;
  final double shimmerWidth;
  final double shimmerHeight;

  @override
  State<RefreshableValue> createState() => _RefreshableValueState();
}

class _RefreshableValueState extends State<RefreshableValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settled = AnimationController(
    vsync: this,
    value: widget.refreshing ? 0 : 1,
  );

  @override
  void didUpdateWidget(RefreshableValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshing != widget.refreshing) {
      _settled.animateTo(
        widget.refreshing ? 0 : 1,
        duration: Duration(milliseconds: widget.refreshing ? 140 : 280),
        curve: Curves.easeInOutQuad,
      );
    }
  }

  @override
  void dispose() {
    _settled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settled,
      child: widget.child,
      builder: (context, child) {
        final s = _settled.value;
        return Stack(
          alignment: Alignment.centerRight,
          children: [
            Opacity(
              opacity: 0.28 + s * 0.72,
              child: Transform.scale(scale: 0.985 + s * 0.015, child: child),
            ),
            if (s < 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Opacity(
                      opacity: 1 - s,
                      child: Shimmer(
                        width: widget.shimmerWidth,
                        height: widget.shimmerHeight,
                        radius: widget.shimmerHeight / 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
