import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../painting/marker_stroke.dart';

/// One run of text under a highlighter stroke.
///
/// [fill] is how much of the stroke has been drawn, 0 to 1 from the left, so a
/// sweep can be part way across a word. It is what makes the highlighter read
/// as a hand moving rather than a rectangle appearing.
class TextMark {
  const TextMark({
    required this.start,
    required this.end,
    this.fill = 1,
    this.color,
  });

  final int start;
  final int end;
  final double fill;

  /// Overrides the widget's marker colour, so the current match can be a
  /// heavier alpha of the same hue than its neighbours.
  final Color? color;
}

/// Text with runs struck through with a marker, the way someone would go over
/// a page with a highlighter looking for a word.
///
/// Give it a [query] to mark every case insensitive occurrence, or [marks] to
/// drive each run's position and fill yourself. With neither this is an
/// ordinary line of text.
class MarkedText extends LeafRenderObjectWidget {
  const MarkedText(
    this.text, {
    super.key,
    required this.style,
    required this.markerColor,
    this.query = '',
    this.marks = const [],
    this.maxLines,
    this.ellipsis,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;

  /// What to look for, matched without regard to case.
  final String query;

  /// Explicit runs, which win over [query] when they are given.
  final List<TextMark> marks;

  final Color markerColor;
  final int? maxLines;
  final String? ellipsis;
  final TextAlign textAlign;

  @override
  RenderMarkedText createRenderObject(BuildContext context) {
    return RenderMarkedText(
      text,
      style,
      query,
      marks,
      markerColor,
      maxLines,
      ellipsis,
      textAlign,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderMarkedText renderObject) {
    renderObject
      ..text = text
      ..style = style
      ..query = query
      ..marks = marks
      ..markerColor = markerColor
      ..maxLines = maxLines
      ..ellipsis = ellipsis
      ..textAlign = textAlign
      ..textScaler = MediaQuery.textScalerOf(context)
      ..textDirection = Directionality.of(context);
  }
}

/// Lays the text out once and paints the marker under the glyphs.
class RenderMarkedText extends RenderBox {
  RenderMarkedText(
    this._text,
    this._style,
    this._query,
    this._marks,
    this._markerColor,
    this._maxLines,
    this._ellipsis,
    this._textAlign,
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

  List<TextMark> _marks;
  set marks(List<TextMark> value) {
    if (identical(_marks, value)) return;
    _marks = value;
    markNeedsPaint();
  }

  Color _markerColor;
  set markerColor(Color value) {
    if (_markerColor == value) return;
    _markerColor = value;
    markNeedsPaint();
  }

  int? _maxLines;
  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    markNeedsLayout();
  }

  String? _ellipsis;
  set ellipsis(String? value) {
    if (_ellipsis == value) return;
    _ellipsis = value;
    markNeedsLayout();
  }

  TextAlign _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsLayout();
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
      ..maxLines = _maxLines
      ..ellipsis = _ellipsis
      ..textAlign = _textAlign
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

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return _painter.computeDistanceToActualBaseline(baseline);
  }

  /// The runs to paint: the explicit [marks] if there are any, otherwise every
  /// place [query] occurs.
  List<TextMark> _runs() {
    if (_marks.isNotEmpty) {
      return _marks;
    }
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const [];
    }
    final haystack = _text.toLowerCase();
    final runs = <TextMark>[];
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) {
        return runs;
      }
      runs.add(TextMark(start: at, end: at + needle.length));
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
    for (final run in _runs()) {
      if (run.end <= run.start || run.fill <= 0) {
        continue;
      }
      final paint = Paint()..color = run.color ?? _markerColor;
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: run.start, extentOffset: run.end),
      );
      for (final box in boxes) {
        paintMarkerStroke(
          canvas,
          box.toRect().shift(offset),
          paint,
          fill: run.fill,
        );
      }
    }
    _painter.paint(canvas, offset);
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
