import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lets a control answer to touches that land a little outside it, so a small
/// target is still comfortable to hit.
class HitSlop extends SingleChildRenderObjectWidget {
  const HitSlop({super.key, required this.slop, required Widget super.child});

  /// How far beyond the control's edges a touch still counts.
  final double slop;

  @override
  RenderHitSlop createRenderObject(BuildContext context) => RenderHitSlop(slop);

  @override
  void updateRenderObject(BuildContext context, RenderHitSlop renderObject) {
    renderObject.slop = slop;
  }
}

/// Accepts a touch inside the grown rectangle and hands the child the nearest
/// point it owns, so the control reacts as if the touch had landed on it.
class RenderHitSlop extends RenderProxyBox {
  RenderHitSlop(this._slop);

  double _slop;

  double get slop => _slop;

  set slop(double value) {
    if (value != _slop) {
      _slop = value;
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.isEmpty) {
      return false;
    }
    final grown = Rect.fromLTRB(
      -_slop,
      -_slop,
      size.width + _slop,
      size.height + _slop,
    );
    if (!grown.contains(position)) {
      return false;
    }
    return super.hitTest(
      result,
      position: Offset(
        position.dx.clamp(0, size.width - 0.01),
        position.dy.clamp(0, size.height - 0.01),
      ),
    );
  }
}
