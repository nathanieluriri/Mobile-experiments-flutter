import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Text with every run matching [query] struck through with a marker, the way
/// someone would go over a page with a highlighter looking for a word.
///
/// With an empty query this is an ordinary line of text.
class MarkedText extends LeafRenderObjectWidget {
  const MarkedText(
    this.text, {
    super.key,
    required this.style,
    required this.query,
    required this.markerColor,
  });

  final String text;
  final TextStyle style;

  /// What to look for, matched without regard to case.
  final String query;

  final Color markerColor;

  @override
  RenderMarkedText createRenderObject(BuildContext context) {
    return RenderMarkedText(
      text,
      style,
      query,
      markerColor,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMarkedText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..query = query
      ..markerColor = markerColor
      ..textScaler = MediaQuery.textScalerOf(context)
      ..textDirection = Directionality.of(context);
  }
}

class RenderMarkedText extends RenderBox {
  RenderMarkedText(
    this._text,
    this._style,
    this._query,
    this._markerColor,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    _painter
      ..textScaler = textScaler
      ..textDirection = textDirection;
  }

  final TextPainter _painter = TextPainter();

  String _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  TextStyle _style;
  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsLayout();
  }

  String _query;
  set query(String value) {
    if (_query == value) return;
    _query = value;
    markNeedsPaint();
  }

  Color _markerColor;
  set markerColor(Color value) {
    if (_markerColor == value) return;
    _markerColor = value;
    markNeedsPaint();
  }

  set textScaler(TextScaler value) {
    if (_painter.textScaler == value) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  void _layoutText(double maxWidth) {
    _painter
      ..text = TextSpan(text: _text, style: _style)
      ..layout(maxWidth: maxWidth);
  }

  @override
  void performLayout() {
    _layoutText(constraints.maxWidth);
    size = constraints.constrain(_painter.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _layoutText(constraints.maxWidth);
    return constraints.constrain(_painter.size);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _layoutText(double.infinity);
    return _painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutText(double.infinity);
    return _painter.maxIntrinsicWidth;
  }

  /// Where [_query] sits in the text, as start offsets.
  Iterable<int> _matches() sync* {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return;
    }
    final haystack = _text.toLowerCase();
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) {
        return;
      }
      yield at;
      from = at + needle.length;
    }
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _text
      ..textDirection = _painter.textDirection;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final length = _query.trim().length;
    if (length > 0) {
      final paint = Paint()..color = _markerColor;
      for (final start in _matches()) {
        final boxes = _painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + length),
        );
        for (final box in boxes) {
          canvas.drawPath(_stroke(box.toRect().shift(offset)), paint);
        }
      }
    }
    _painter.paint(canvas, offset);
  }

  /// A marker stroke over the word: a touch wider than the glyphs, sitting off
  /// the baseline, and leaning the way a hand holding a pen would lean it.
  Path _stroke(Rect box) {
    const lean = 1.6;
    const overhang = 2.0;
    final top = box.top + box.height * 0.14;
    final bottom = box.bottom - box.height * 0.08;
    return Path()
      ..moveTo(box.left - overhang + lean, top)
      ..lineTo(box.right + overhang + lean, top)
      ..lineTo(box.right + overhang - lean, bottom)
      ..lineTo(box.left - overhang - lean, bottom)
      ..close();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
