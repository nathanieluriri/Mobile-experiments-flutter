import 'dart:typed_data';
import 'dart:ui' show Rect;

/// A 2D affine matrix in PDF order: [a b c d e f].
class Mat {
  const Mat(this.a, this.b, this.c, this.d, this.e, this.f);
  const Mat.identity() : this(1, 0, 0, 1, 0, 0);
  final double a, b, c, d, e, f;

  /// this * m (apply `this` first, then `m`).
  Mat mul(Mat m) => Mat(
        a * m.a + b * m.c,
        a * m.b + b * m.d,
        c * m.a + d * m.c,
        c * m.b + d * m.d,
        e * m.a + f * m.c + m.e,
        e * m.b + f * m.d + m.f,
      );

  double tx(double x, double y) => a * x + c * y + e;
  double ty(double x, double y) => b * x + d * y + f;

  /// Uniform-ish scale, used to turn a text matrix into a font size.
  double get scaleY {
    final v = (b * b + d * d);
    return v <= 0 ? 0 : _sqrt(v);
  }

  double get scaleX {
    final v = (a * a + c * c);
    return v <= 0 ? 0 : _sqrt(v);
  }

  static double _sqrt(double v) {
    var x = v;
    if (x <= 0) return 0;
    for (var i = 0; i < 20; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }

  @override
  String toString() => '[$a $b $c $d $e $f]';
}

/// A run of glyphs sharing one font, size and baseline.
class TextRunCmd {
  TextRunCmd({
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.widthPts,
    required this.fontKey,
    required this.bold,
    required this.italic,
    required this.serif,
    required this.mono,
    required this.color,
    required this.rotated,
    required this.seq,
  });

  /// Unicode text of the run.
  final String text;

  /// Baseline origin in top-left page space (y grows downward).
  final double x, y;
  final double fontSize;
  final double widthPts;
  final String fontKey;
  final bool bold, italic, serif, mono;
  final int color;
  final bool rotated;
  final int seq;

  @override
  String toString() =>
      'Text("$text") @(${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}) '
      'size=${fontSize.toStringAsFixed(1)} w=${widthPts.toStringAsFixed(1)}';
}

enum PathOp { move, line, cubic, close }

class PathSeg {
  const PathSeg(this.op, this.pts);
  final PathOp op;
  final List<double> pts;
}

class PathCmd {
  PathCmd({
    required this.segs,
    required this.fill,
    required this.stroke,
    required this.fillColor,
    required this.strokeColor,
    required this.lineWidth,
    required this.evenOdd,
    required this.seq,
  });
  final List<PathSeg> segs;
  final bool fill, stroke, evenOdd;
  final int fillColor, strokeColor;
  final double lineWidth;
  final int seq;
}

class ImageCmd {
  ImageCmd({
    required this.name,
    required this.rect,
    required this.bytes,
    required this.encoding,
    required this.width,
    required this.height,
    required this.seq,
  });
  final String name;

  /// Destination rect in top-left page space: [l, t, r, b].
  final List<double> rect;

  /// Encoded bytes ready for a decoder, or null when unsupported.
  final Uint8List? bytes;

  /// 'jpeg', 'raw-rgb', 'raw-gray', 'jpx', 'ccitt', 'unsupported'.
  final String encoding;
  final int width, height;
  final int seq;

  @override
  String toString() =>
      'Image($name $encoding ${width}x$height -> ${rect.map((e) => e.round()).toList()})';
}

/// Everything needed to paint one page.
class PageDisplayList {
  PageDisplayList({
    required this.widthPts,
    required this.heightPts,
    required this.rotation,
  });
  final double widthPts, heightPts;
  final int rotation;
  final List<TextRunCmd> texts = [];
  final List<PathCmd> paths = [];
  final List<ImageCmd> images = [];

  /// Fraction of the page area covered by images: a rough "is this a scan?"
  /// signal for choosing the fallback presentation.
  double get imageCoverage {
    if (widthPts <= 0 || heightPts <= 0) return 0;
    var area = 0.0;
    for (final im in images) {
      final w = (im.rect[2] - im.rect[0]).abs();
      final h = (im.rect[3] - im.rect[1]).abs();
      area += w * h;
    }
    return area / (widthPts * heightPts);
  }
}


/// The horizontal gap, as a fraction of the type size, above which two runs on
/// one baseline are a word break rather than kerning.
///
/// Producers express a space either as a space glyph or as pure positioning,
/// and only the distance tells the two apart. Set too low, a kerning pair
/// becomes a space and a word shatters into `outsi d e`. Set too high, a real
/// break is swallowed and two words run together as `theseare`.
///
/// Swept from 0.005 to 0.25 over eleven real documents against a reference
/// extractor: below 0.023 the score collapses (word-level F1 0.825, and 1,087
/// stray single letters against 134), and above 0.028 recall falls away
/// steadily as real breaks are missed. The plateau is 0.023 to 0.028, so the
/// value sits in the middle of it with room on both sides.
///
/// Neither bundled document can decide this: every word break in both of them
/// is an explicit space glyph, so their merged text is the same at any
/// threshold. The tests assert that invariance rather than pretending to
/// tune against it.
const double kWordGapEm = 0.026;

/// Adjacent runs on the same baseline merged into one paintable line.
class LaidOutRun {
  LaidOutRun(this.text, this.x, this.y, this.size, this.width, this.style,
      this.color, this.seq);

  /// The merged unicode text of the line.
  final String text;

  /// Baseline origin in top-left page space, the type size, and the width the
  /// PDF says this run occupies.
  final double x, y, size, width;

  /// Bit 0 bold, bit 1 italic, bit 2 serif, bit 3 mono.
  final int style;
  final int color;

  /// The content stream position of the first run in the merge, which is what
  /// the ordered paint pass and every effect that walks the page read from.
  final int seq;

  bool get bold => (style & 1) != 0;
  bool get italic => (style & 2) != 0;
  bool get serif => (style & 4) != 0;
  bool get mono => (style & 8) != 0;

  /// The box this line paints into, in top-left page space.
  ///
  /// The painter draws from `y - size * 0.8`, so a highlight drawn over this
  /// rect covers exactly the glyphs and not the line above.
  Rect get bounds => Rect.fromLTWH(x, y - size * 0.8, width, size);

  /// The box around characters [start] to [end] of [text], interpolated across
  /// [width]. Glyph-exact positions are gone by merge time, and a proportional
  /// slice is what lets a match be highlighted without re-running the page.
  Rect sliceBounds(int start, int end) {
    if (text.isEmpty || width <= 0) return bounds;
    final n = text.length;
    final a = (start.clamp(0, n)) / n;
    final b = (end.clamp(0, n)) / n;
    return Rect.fromLTWH(
        x + width * a, y - size * 0.8, width * (b - a).abs(), size);
  }

  @override
  String toString() =>
      'Run("$text") @(${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}) '
      'size=${size.toStringAsFixed(1)} w=${width.toStringAsFixed(1)}';
}

int _styleOf(TextRunCmd r) =>
    (r.bold ? 1 : 0) | (r.italic ? 2 : 0) | (r.serif ? 4 : 0) | (r.mono ? 8 : 0);

/// Merges per-glyph or per-fragment runs into line-level runs.
///
/// A dense page emits thousands of runs, one per glyph cluster the producer
/// happened to emit. Painting them one by one means one `TextPainter` each, and
/// searching them means a word is never whole. Merging on baseline, style and a
/// sane gap gives back the lines a person would read.
///
/// [wordGapEm] is the threshold above which a horizontal gap becomes a space.
/// It is a parameter so it can be swept over a corpus and pinned by evidence,
/// not by taste.
List<LaidOutRun> mergeRuns(List<TextRunCmd> runs,
    {double wordGapEm = kWordGapEm}) {
  if (runs.isEmpty) return const [];
  final sorted = List<TextRunCmd>.from(runs)
    ..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      return dy != 0 ? dy : a.x.compareTo(b.x);
    });
  final out = <LaidOutRun>[];
  var buf = StringBuffer();
  var startX = sorted.first.x;
  var lineY = sorted.first.y;
  var size = sorted.first.fontSize;
  var style = _styleOf(sorted.first);
  var color = sorted.first.color;
  var cursor = sorted.first.x;
  var seq = sorted.first.seq;

  void flush(double endX) {
    final s = buf.toString();
    if (s.trim().isNotEmpty) {
      out.add(
          LaidOutRun(s, startX, lineY, size, endX - startX, style, color, seq));
    }
    buf = StringBuffer();
  }

  for (var i = 0; i < sorted.length; i++) {
    final r = sorted[i];
    if (i == 0) {
      buf.write(r.text);
      cursor = r.x + r.widthPts;
      continue;
    }
    final sameLine = (r.y - lineY).abs() <= size * 0.3;
    final sameStyle = _styleOf(r) == style &&
        (r.fontSize - size).abs() < 0.6 &&
        r.color == color;
    final gap = r.x - cursor;
    if (sameLine && sameStyle && gap > -size * 0.6 && gap < size * 1.2) {
      // A gap this wide is a word break the producer expressed as positioning
      // rather than as a space glyph.
      if (gap > size * wordGapEm && !buf.toString().endsWith(' ')) {
        buf.write(' ');
      }
      buf.write(r.text);
      cursor = r.x + r.widthPts;
      continue;
    }
    flush(cursor);
    startX = r.x;
    lineY = r.y;
    size = r.fontSize;
    style = _styleOf(r);
    color = r.color;
    seq = r.seq;
    buf.write(r.text);
    cursor = r.x + r.widthPts;
  }
  flush(cursor);
  return out;
}
