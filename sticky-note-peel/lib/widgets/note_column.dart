import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class _NoteColumnParentData extends ContainerBoxParentData<RenderBox> {}

/// Stacks the list vertically with a fixed gap, and adds two things a plain
/// [Column] cannot do.
///
/// A lifted note paints its fold and its dock outside its own box, over the
/// notes below it, so [paintLast] pulls one child to the front of the paint and
/// hit-test order without moving it.
///
/// When a note is removed the gap it leaves has to close smoothly, so
/// [extraSpace] holds that many pixels open before child [extraSpaceIndex] and
/// the caller springs it down to zero.
class NoteColumn extends MultiChildRenderObjectWidget {
  const NoteColumn({
    super.key,
    required this.gap,
    this.paintLast,
    this.extraSpaceIndex,
    this.extraSpace = 0,
    required super.children,
  });

  final double gap;
  final int? paintLast;
  final int? extraSpaceIndex;
  final double extraSpace;

  @override
  RenderNoteColumn createRenderObject(BuildContext context) {
    return RenderNoteColumn(gap, paintLast, extraSpaceIndex, extraSpace);
  }

  @override
  void updateRenderObject(BuildContext context, RenderNoteColumn renderObject) {
    renderObject
      ..gap = gap
      ..paintLast = paintLast
      ..extraSpaceIndex = extraSpaceIndex
      ..extraSpace = extraSpace;
  }
}

class RenderNoteColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _NoteColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _NoteColumnParentData> {
  RenderNoteColumn(
    this._gap,
    this._paintLast,
    this._extraSpaceIndex,
    this._extraSpace,
  );

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  int? _paintLast;
  int? get paintLast => _paintLast;
  set paintLast(int? value) {
    if (_paintLast == value) return;
    _paintLast = value;
    markNeedsPaint();
  }

  int? _extraSpaceIndex;
  int? get extraSpaceIndex => _extraSpaceIndex;
  set extraSpaceIndex(int? value) {
    if (_extraSpaceIndex == value) return;
    _extraSpaceIndex = value;
    markNeedsLayout();
  }

  double _extraSpace;
  double get extraSpace => _extraSpace;
  set extraSpace(double value) {
    if (_extraSpace == value) return;
    _extraSpace = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _NoteColumnParentData) {
      child.parentData = _NoteColumnParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var y = 0.0;
    var index = 0;
    var child = firstChild;
    while (child != null) {
      if (index == _extraSpaceIndex) {
        y += _extraSpace;
      }
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      (child.parentData! as _NoteColumnParentData).offset = Offset(0, y);
      y += child.size.height;
      child = childAfter(child);
      if (child != null) {
        y += _gap;
      }
      index++;
    }
    if (_extraSpaceIndex == index) {
      y += _extraSpace;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    var y = _extraSpace;
    var child = firstChild;
    while (child != null) {
      y += child.getDryLayout(BoxConstraints.tightFor(width: width)).height;
      child = childAfter(child);
      if (child != null) {
        y += _gap;
      }
    }
    return constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final children = getChildrenAsList();
    final last = _paintLast;
    for (var i = 0; i < children.length; i++) {
      if (i != last) {
        _paintChild(context, children[i], offset);
      }
    }
    if (last != null && last >= 0 && last < children.length) {
      _paintChild(context, children[last], offset);
    }
  }

  void _paintChild(PaintingContext context, RenderBox child, Offset offset) {
    final data = child.parentData! as _NoteColumnParentData;
    context.paintChild(child, data.offset + offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final children = getChildrenAsList();
    final last = _paintLast;
    if (last != null && last >= 0 && last < children.length) {
      if (_hitTestChild(result, children[last], position)) {
        return true;
      }
    }
    for (var i = children.length - 1; i >= 0; i--) {
      if (i == last) continue;
      if (_hitTestChild(result, children[i], position)) {
        return true;
      }
    }
    return false;
  }

  bool _hitTestChild(
    BoxHitTestResult result,
    RenderBox child,
    Offset position,
  ) {
    final data = child.parentData! as _NoteColumnParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return child.hitTest(result, position: transformed);
      },
    );
  }
}
