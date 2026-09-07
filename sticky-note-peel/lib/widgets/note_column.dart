import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class NoteColumnParentData extends ContainerBoxParentData<RenderBox> {
  /// How much of its own slot this child is taking up, 0 to 1. A note arriving
  /// grows its slot from nothing; a note leaving closes it again.
  double factor = 1;
}

/// How much room the child inside it is taking in the column. At 1 the child
/// gets its full height and the gap above it; at 0 it takes no room at all and
/// is not drawn.
class NoteSlot extends ParentDataWidget<NoteColumnParentData> {
  const NoteSlot({super.key, required this.factor, required super.child});

  final double factor;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as NoteColumnParentData;
    if (data.factor == factor) {
      return;
    }
    data.factor = factor;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => NoteColumn;
}

/// Stacks the list vertically with a fixed gap, and adds three things a plain
/// [Column] cannot do.
///
/// A lifted note paints its fold and its dock outside its own box, over the
/// notes below it, so [paintLast] pulls one child to the front of the paint and
/// hit-test order without moving it.
///
/// A note arriving or leaving opens and closes its own slot, through the
/// [NoteSlot] wrapped around it.
///
/// When a note is removed after being dropped on the dock it has already
/// shrunk to nothing on its own, so [extraSpace] holds the room it vacated open
/// before child [extraSpaceIndex] and the caller springs it shut.
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
        ContainerRenderObjectMixin<RenderBox, NoteColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, NoteColumnParentData> {
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
    if (child.parentData is! NoteColumnParentData) {
      child.parentData = NoteColumnParentData();
    }
  }

  double _factorOf(RenderBox child) =>
      (child.parentData! as NoteColumnParentData).factor.clamp(0.0, 1.0);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var y = 0.0;
    var index = 0;
    var anyPlaced = false;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as NoteColumnParentData;
      if (index == _extraSpaceIndex) {
        y += _extraSpace;
      }
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      final factor = _factorOf(child);
      // The gap belongs to the child below it, so a child that is not there
      // takes neither its own height nor the space above it.
      if (anyPlaced) {
        y += _gap * factor;
      }
      data.offset = Offset(0, y);
      y += child.size.height * factor;
      if (factor > 0) {
        anyPlaced = true;
      }
      child = childAfter(child);
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
    var anyPlaced = false;
    var child = firstChild;
    while (child != null) {
      final factor = _factorOf(child);
      if (anyPlaced) {
        y += _gap * factor;
      }
      y += child.getDryLayout(BoxConstraints.tightFor(width: width)).height *
          factor;
      if (factor > 0) {
        anyPlaced = true;
      }
      child = childAfter(child);
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
    final data = child.parentData! as NoteColumnParentData;
    final factor = _factorOf(child);
    if (factor <= 0) {
      return;
    }
    if (factor >= 1) {
      context.paintChild(child, data.offset + offset);
      return;
    }
    // Half a slot shows the top half of the note, so it reads as being drawn
    // out of the list rather than squashed into it.
    context.pushClipRect(
      needsCompositing,
      offset + data.offset,
      Offset.zero & Size(child.size.width, child.size.height * factor),
      (innerContext, innerOffset) => innerContext.paintChild(child, innerOffset),
    );
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
    if (_factorOf(child) <= 0) {
      return false;
    }
    final data = child.parentData! as NoteColumnParentData;
    return result.addWithPaintOffset(
      offset: data.offset,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return child.hitTest(result, position: transformed);
      },
    );
  }
}
