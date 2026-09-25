import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../pdf/display_list.dart';
import '../theme/colors.dart';

export '../pdf/display_list.dart' show LaidOutRun, mergeRuns, kWordGapEm;

/// A merged line of a page, set in the app's typeface the way the page paints
/// it, laid out and ready to paint or measure.
///
/// A line the file spreads far wider than the typeface sets it is letter
/// spaced, which is how a tracked heading like `S L I D E` is drawn, so it is
/// opened up by spacing rather than by stretching every letter.
TextPainter setRun(
  LaidOutRun r, {
  required String serifFamily,
  required String sansFamily,
}) {
  TextPainter set(double spacing) => TextPainter(
        text: TextSpan(
          text: r.text,
          style: TextStyle(
            fontFamily: (r.style & 4) != 0 ? serifFamily : sansFamily,
            fontSize: r.size,
            height: 1.0,
            letterSpacing: spacing,
            fontWeight: (r.style & 1) != 0 ? FontWeight.w700 : FontWeight.w400,
            fontStyle: (r.style & 2) != 0 ? FontStyle.italic : FontStyle.normal,
            color: Color(r.color),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
  final plain = set(0);
  final letters = r.text.runes.length;
  if (letters < 2 || plain.width <= 0 || r.width / plain.width < kSqueezeMax) {
    return plain;
  }
  final spacing = (r.width - plain.width) / letters;
  plain.dispose();
  return set(spacing);
}

/// The narrowest and widest a line is fitted to the width the file gives it.
const double kSqueezeMin = 0.55;
const double kSqueezeMax = 1.8;

/// How far [set] is squeezed or stretched across to fill the width the file
/// says the line occupies, so line breaks and column edges land where they
/// should.
///
/// A line far wider than the typeface is letter spaced by [setRun] instead.
/// A line far narrower is squeezed only as far as still reads, and the
/// painter clips what is left over, because letting it run on paints it over
/// whatever the file put next to it.
double runSqueeze(LaidOutRun r, TextPainter set) {
  if (r.width <= 0 || set.width <= 0) return 1.0;
  final sx = r.width / set.width;
  if (sx >= kSqueezeMax) return 1.0;
  return sx < kSqueezeMin ? kSqueezeMin : sx;
}

/// The box characters [start] to [end] of [run] occupy as the page paints
/// them, in the page's own points.
///
/// The search can only interpolate across a line, because it never sees the
/// typeface. This measures the letters where they are actually set, so a
/// highlighter over a word covers that word and not a slice of the line that
/// happens to be as long. Each answer is kept against its line, because a
/// sweep asks again every frame it runs.
Rect paintedSlice(
  LaidOutRun run,
  int start,
  int end, {
  required String serifFamily,
  required String sansFamily,
}) {
  final held = _slices[run] ??= <(int, int), Rect>{};
  return held[(start, end)] ??= () {
    if (run.angle != 0) return run.bounds;
    final set = setRun(run, serifFamily: serifFamily, sansFamily: sansFamily);
    final squeeze = runSqueeze(run, set);
    final letters = set.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    set.dispose();
    if (letters.isEmpty) return run.sliceBounds(start, end);
    var left = double.infinity;
    var right = double.negativeInfinity;
    for (final box in letters) {
      left = math.min(left, box.left);
      right = math.max(right, box.right);
    }
    return Rect.fromLTWH(
      run.x + left * squeeze,
      run.y - run.size * 0.8,
      (right - left) * squeeze,
      run.size,
    );
  }();
}

final Expando<Map<(int, int), Rect>> _slices = Expando<Map<(int, int), Rect>>();

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
      Paint()..color = AppColors.page,
    );

    // One ordered pass. Painting images, then paths, then text in separate
    // passes destroys the z-order a PDF depends on, so every command carries
    // the sequence number it had in the content stream.
    final ops = <(int, Object)>[
      for (final im in list.images) (im.seq, im),
      if (drawPaths) for (final sh in list.shades) (sh.seq, sh),
      if (drawPaths) for (final p in list.paths) (p.seq, p),
      for (final r in runs) (r.seq, r),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    var inside = kNoClip;
    for (final (_, cmd) in ops) {
      final clip = switch (cmd) {
        ImageCmd() => cmd.clip,
        ShadeCmd() => cmd.clip,
        PathCmd() => cmd.clip,
        LaidOutRun() => cmd.clip,
        _ => kNoClip,
      };
      if (clip != inside) {
        if (inside != kNoClip) canvas.restore();
        inside = clip;
        if (clip != kNoClip && clip < list.clips.length) {
          canvas.save();
          for (final path in list.clips[clip].paths) {
            canvas.clipPath(_pathOf(path.segs, path.evenOdd));
          }
        } else {
          inside = kNoClip;
        }
      }
      if (cmd is ImageCmd) {
        _image(canvas, cmd);
      } else if (cmd is ShadeCmd) {
        _shade(canvas, cmd);
      } else if (cmd is PathCmd) {
        _path(canvas, cmd);
      } else if (cmd is LaidOutRun) {
        _text(canvas, cmd);
      }
    }
    if (inside != kNoClip) canvas.restore();
    canvas.restore();
  }

  /// A shading over its whole clip region, or the whole page when it has
  /// none, drawn in its own space so the blend runs the way the file set it.
  void _shade(Canvas canvas, ShadeCmd s) {
    final m = s.matrix;
    final det = m.a * m.d - m.b * m.c;
    if (det.abs() < 1e-12 || s.colors.length < 2) return;
    final colors = [for (final c in s.colors) Color(c)];
    final stops = [
      for (var i = 0; i < colors.length; i++) i / (colors.length - 1),
    ];
    // An unextended end leaves the page bare past it. When only one end
    // extends the blend is extended both ways, which is rare and close.
    final tile = s.extendStart || s.extendEnd ? TileMode.clamp : TileMode.decal;
    final c = s.coords;
    final ui.Gradient gradient = s.radial
        ? ui.Gradient.radial(
            Offset(c[3], c[4]),
            c[5],
            colors,
            stops,
            tile,
            null,
            Offset(c[0], c[1]),
            c[2],
          )
        : ui.Gradient.linear(
            Offset(c[0], c[1]),
            Offset(c[2], c[3]),
            colors,
            stops,
            tile,
          );
    canvas
      ..save()
      ..transform(Float64List.fromList(<double>[
        m.a, m.b, 0, 0, //
        m.c, m.d, 0, 0,
        0, 0, 1, 0,
        m.e, m.f, 0, 1,
      ]))
      ..drawPaint(Paint()..shader = gradient)
      ..restore();
  }

  void _image(Canvas canvas, ImageCmd im) {
    final img = images[im.name];
    if (img == null) return;
    final source = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final into = Rect.fromLTRB(im.rect[0], im.rect[1], im.rect[2], im.rect[3]);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final turns = (list.rotation ~/ 90) % 4;
    if (turns == 0) {
      canvas.drawImageRect(img, source, into, paint);
      return;
    }
    // Turned about the middle of the rectangle it was placed in, so a scan
    // fed in sideways comes out the way it was written.
    canvas.save();
    canvas.translate(into.center.dx, into.center.dy);
    canvas.rotate(turns * math.pi / 2);
    canvas.drawImageRect(
      img,
      source,
      Rect.fromCenter(
        center: Offset.zero,
        width: turns.isOdd ? into.height : into.width,
        height: turns.isOdd ? into.width : into.height,
      ),
      paint,
    );
    canvas.restore();
  }

  static Path _pathOf(List<PathSeg> segs, bool evenOdd) {
    final path = Path()
      ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    for (final s in segs) {
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
    return path;
  }

  void _path(Canvas canvas, PathCmd p) {
    final path = _pathOf(p.segs, p.evenOdd);
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
    final tp = setRun(r, serifFamily: serifFamily, sansFamily: sansFamily);
    final squeeze = runSqueeze(r, tp);
    canvas.save();
    canvas.translate(r.x, r.y);
    if (r.angle != 0) canvas.rotate(r.angle);
    if (r.width > 0 && tp.width * squeeze > r.width + r.size * 0.5) {
      canvas.clipRect(
          Rect.fromLTWH(-r.size, -r.size * 1.2, r.width + r.size * 1.5, r.size * 1.6));
    }
    canvas.scale(squeeze, 1);
    tp.paint(canvas, Offset(0, -r.size * 0.8));
    tp.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageListPainter old) =>
      old.list != list || old.runs != runs || old.images != images;
}
