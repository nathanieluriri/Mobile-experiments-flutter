import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'marker_stroke.dart';

/// One highlighter stroke on a page, in the page's own points.
@immutable
class PageMark {
  const PageMark({
    required this.box,
    required this.fill,
    required this.color,
    this.run,
    this.start = 0,
    this.end = 0,
  });

  /// The box the marked letters occupy, from the page's top left, in points.
  final Rect box;

  /// Which of the page's lines the letters are in, and where along it, for a
  /// page that can measure them exactly rather than trust [box].
  final int? run;
  final int start;
  final int end;

  /// The same mark over [exact] instead.
  PageMark over(Rect exact) => PageMark(
    box: exact,
    fill: fill,
    color: color,
    run: run,
    start: start,
    end: end,
  );

  /// How much of the stroke is drawn, 0 to 1 from the left.
  final double fill;

  final Color color;
}

/// Goes over the letters a find turned up on one page with a highlighter.
///
/// It paints over the page rather than under it, because a page file fills
/// its own ground and anything under that fill would never be seen. It
/// multiplies rather than covers, which is what a real highlighter does to
/// printed paper: the paper takes the colour and the ink stays black.
class PageMarksPainter extends CustomPainter {
  const PageMarksPainter({required this.marks, required this.pageWidthPts});

  final List<PageMark> marks;

  /// How wide the page is in its own points, which is what turns a box on the
  /// page into a box on the screen at whatever size it is drawn.
  final double pageWidthPts;

  @override
  void paint(Canvas canvas, Size size) {
    if (marks.isEmpty || pageWidthPts <= 0) return;
    final scale = size.width / pageWidthPts;
    for (final mark in marks) {
      if (mark.fill <= 0) continue;
      final box = Rect.fromLTWH(
        mark.box.left * scale,
        mark.box.top * scale,
        mark.box.width * scale,
        mark.box.height * scale,
      );
      paintMarkerStroke(
        canvas,
        box,
        Paint()
          ..color = mark.color
          ..blendMode = BlendMode.multiply,
        fill: mark.fill,
        lean: box.height * kMarkerLeanShare,
        overhang: box.height * kMarkerOverhangShare,
      );
    }
  }

  @override
  bool shouldRepaint(PageMarksPainter old) =>
      !identical(old.marks, marks) || old.pageWidthPts != pageWidthPts;
}
