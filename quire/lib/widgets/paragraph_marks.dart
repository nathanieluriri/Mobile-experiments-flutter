import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../painting/marker_stroke.dart';
import 'marked_text.dart';

/// A paragraph with highlighter strokes under some of its runs.
///
/// [MarkedText] lays out its own plain string. A document's paragraphs are
/// span trees, bold and italic and links and inline code, so this goes the
/// other way: [child] lays its text out however it likes, and the strokes are
/// put under the runs of the first paragraph it laid out, before its letters
/// are painted over them.
///
/// The offsets in [marks] are offsets into that paragraph's laid out text.
class ParagraphMarks extends SingleChildRenderObjectWidget {
  const ParagraphMarks({
    super.key,
    required this.marks,
    required this.markerColor,
    required super.child,
  });

  final List<TextMark> marks;

  /// The colour of a mark that does not name its own.
  final Color markerColor;

  @override
  RenderParagraphMarks createRenderObject(BuildContext context) =>
      RenderParagraphMarks(marks, markerColor);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderParagraphMarks renderObject,
  ) {
    renderObject
      ..marks = marks
      ..markerColor = markerColor;
  }
}

class RenderParagraphMarks extends RenderProxyBox {
  RenderParagraphMarks(this._marks, this._markerColor);

  List<TextMark> _marks;
  set marks(List<TextMark> value) {
    if (identical(value, _marks) || (value.isEmpty && _marks.isEmpty)) return;
    _marks = value;
    markNeedsPaint();
  }

  Color _markerColor;
  set markerColor(Color value) {
    if (value == _markerColor) return;
    _markerColor = value;
    markNeedsPaint();
  }

  /// The paragraph the strokes go under: the first one below this box.
  RenderParagraph? get paragraph {
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final below = child;
    if (below != null) visit(below);
    return found;
  }

  /// Where the letters from [start] to [end] are set, in this box's own
  /// coordinates, one rect per line they run across.
  List<Rect> rectsOf(int start, int end) {
    final text = paragraph;
    if (text == null || end <= start || !hasSize) return const <Rect>[];
    final origin = MatrixUtils.transformPoint(
      text.getTransformTo(this),
      Offset.zero,
    );
    return <Rect>[
      for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      ))
        box.toRect().shift(origin),
    ];
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_marks.isNotEmpty) {
      final canvas = context.canvas;
      for (final mark in _marks) {
        if (mark.fill <= 0) continue;
        final paint = Paint()..color = mark.color ?? _markerColor;
        for (final rect in rectsOf(mark.start, mark.end)) {
          paintMarkerStroke(canvas, rect.shift(offset), paint, fill: mark.fill);
        }
      }
    }
    super.paint(context, offset);
  }
}
