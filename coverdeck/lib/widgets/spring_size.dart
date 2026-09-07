import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Springs its own size toward its child's whenever the child's layout
/// changes, so a change of shape eases across the whole difference instead of
/// snapping to it.
///
/// The child keeps its own size and is centred, so the caller is expected to
/// clip whatever hangs over the edges while the size catches up.
class SpringSize extends SingleChildRenderObjectWidget {
  const SpringSize({
    super.key,
    required this.vsync,
    required this.spring,
    required Widget super.child,
  });

  final TickerProvider vsync;
  final SpringDescription spring;

  @override
  RenderSpringSize createRenderObject(BuildContext context) =>
      RenderSpringSize(vsync: vsync, spring: spring);

  @override
  void updateRenderObject(BuildContext context, RenderSpringSize renderObject) {
    renderObject
      ..vsync = vsync
      ..spring = spring;
  }
}

/// The render object behind [SpringSize].
class RenderSpringSize extends RenderProxyBox {
  RenderSpringSize({required TickerProvider vsync, required this.spring}) {
    _width = AnimationController.unbounded(vsync: vsync)..addListener(_handleTick);
    _height = AnimationController.unbounded(vsync: vsync)..addListener(_handleTick);
  }

  late final AnimationController _width;
  late final AnimationController _height;
  Size? _target;

  /// Set while the first layout seeds the controllers, when marking this box
  /// dirty would be re-dirtying it inside its own layout pass.
  bool _seeding = false;

  void _handleTick() {
    if (_seeding) return;
    markNeedsLayout();
  }

  /// Spring the size follows.
  SpringDescription spring;

  set vsync(TickerProvider value) {
    _width.resync(value);
    _height.resync(value);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    final target = child.size;
    if (_target == null) {
      _seeding = true;
      _width.value = target.width;
      _height.value = target.height;
      _seeding = false;
    } else if (_target != target) {
      _width.animateWith(
        SpringSimulation(spring, _width.value, target.width, _width.velocity),
      );
      _height.animateWith(
        SpringSimulation(spring, _height.value, target.height, _height.velocity),
      );
    }
    _target = target;
    size = constraints.constrain(Size(_width.value, _height.value));
  }

  /// Where the child sits inside the size currently being animated to.
  Offset get _childOffset => Offset(
        (size.width - child!.size.width) / 2,
        (size.height - child!.size.height) / 2,
      );

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.paintChild(child!, offset + _childOffset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _childOffset,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_childOffset.dx, _childOffset.dy, 0, 1);
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }
}
