import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../pdf/display_list.dart';

export '../pdf/display_list.dart' show LaidOutRun, mergeRuns, kWordGapEm;

/// Paints one page of a PDF from its display list.
///
/// Decoded images arrive from the caller, keyed by [ImageCmd.name], because a
/// `dart:ui` decode is asynchronous and `paint` is not: decoding here would
/// mean a page that flickers in a frame late, every frame.
class PageListPainter extends CustomPainter {
  PageListPainter({
    required this.list,
    required this.runs,
    required this.images,
    required this.serifFamily,
    required this.sansFamily,
    this.drawPaths = true,
  });

  final PageDisplayList list;
  final List<LaidOutRun> runs;
  final Map<String, ui.Image> images;
  final String serifFamily, sansFamily;
  final bool drawPaths;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / list.widthPts;
    canvas.save();
    canvas.scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, list.widthPts, list.heightPts),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    // One ordered pass. Painting images, then paths, then text in separate
    // passes destroys the z-order a PDF depends on, so every command carries
    // the sequence number it had in the content stream.
    final ops = <(int, Object)>[
      for (final im in list.images) (im.seq, im),
      if (drawPaths) for (final p in list.paths) (p.seq, p),
      for (final r in runs) (r.seq, r),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    for (final (_, cmd) in ops) {
      if (cmd is ImageCmd) {
        _image(canvas, cmd);
      } else if (cmd is PathCmd) {
        _path(canvas, cmd);
      } else if (cmd is LaidOutRun) {
        _text(canvas, cmd);
      }
    }
    canvas.restore();
  }

  void _image(Canvas canvas, ImageCmd im) {
    final img = images[im.name];
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTRB(im.rect[0], im.rect[1], im.rect[2], im.rect[3]),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _path(Canvas canvas, PathCmd p) {
    final path = Path()
      ..fillType = p.evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    for (final s in p.segs) {
      switch (s.op) {
        case PathOp.move:
          path.moveTo(s.pts[0], s.pts[1]);
          break;
        case PathOp.line:
          path.lineTo(s.pts[0], s.pts[1]);
          break;
        case PathOp.cubic:
          path.cubicTo(s.pts[0], s.pts[1], s.pts[2], s.pts[3], s.pts[4], s.pts[5]);
          break;
        case PathOp.close:
          path.close();
          break;
      }
    }
    if (p.fill) {
      canvas.drawPath(
          path,
          Paint()
            ..color = Color(p.fillColor)
            ..style = PaintingStyle.fill);
    }
    if (p.stroke) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(p.strokeColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = p.lineWidth <= 0 ? 0.6 : p.lineWidth,
      );
    }
  }

  void _text(Canvas canvas, LaidOutRun r) {
    final tp = TextPainter(
      text: TextSpan(
        text: r.text,
        style: TextStyle(
          fontFamily: (r.style & 4) != 0 ? serifFamily : sansFamily,
          fontSize: r.size,
          height: 1.0,
          fontWeight: (r.style & 1) != 0 ? FontWeight.w700 : FontWeight.w400,
          fontStyle: (r.style & 2) != 0 ? FontStyle.italic : FontStyle.normal,
          color: Color(r.color),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // Squeeze or stretch the laid-out text onto the width the PDF says the
    // run occupies, so line breaks and column edges land where they should.
    final sx = (r.width > 0 && tp.width > 0) ? r.width / tp.width : 1.0;
    canvas.save();
    canvas.translate(r.x, r.y - r.size * 0.8);
    if (sx > 0.55 && sx < 1.8) canvas.scale(sx, 1);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageListPainter old) =>
      old.list != list || old.runs != runs || old.images != images;
}
