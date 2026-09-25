import 'dart:math' as math;
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

  /// How long a unit step along x comes out, which is how far a run advances.
  double get scaleX {
    final v = (a * a + b * b);
    return v <= 0 ? 0 : _sqrt(v);
  }

  /// How long a unit step along y comes out.
  double get scaleY {
    final v = (c * c + d * d);
    return v <= 0 ? 0 : _sqrt(v);
  }

  /// The height of a unit square measured square to its baseline.
  ///
  /// A slanted matrix, which is how a producer fakes an italic, makes [scaleY]
  /// longer than the letters are tall.
  double get heightY {
    final sx = scaleX;
    return sx == 0 ? scaleY : (a * d - b * c).abs() / sx;
  }

  /// The direction the baseline runs, in radians clockwise from the page's x.
  double get angle => math.atan2(b, a);

  /// True when the y axis leans away from square to the baseline by more than
  /// a few degrees.
  bool get slanted {
    final sx = scaleX, sy = scaleY;
    if (sx == 0 || sy == 0) return false;
    final cos = (a * c + b * d) / (sx * sy);
    return cos.abs() > 0.1;
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
    this.angle = 0,
    this.spaceWidthPts = 0,
    this.clip = kNoClip,
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

  /// The direction the baseline runs, in radians clockwise, when [rotated].
  final double angle;

  /// How wide the font's own space is at this size, or 0 when it has none.
  final double spaceWidthPts;

  /// The clip region the run is drawn inside, an index into
  /// [PageDisplayList.clips], or [kNoClip].
  final int clip;

  @override
  String toString() =>
      'Text("$text") @(${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}) '
      'size=${fontSize.toStringAsFixed(1)} w=${widthPts.toStringAsFixed(1)}';
}

/// A command drawn inside no clip region but the page.
const int kNoClip = -1;

/// One path of a clip, in top-left page space.
class ClipPath {
  const ClipPath(this.segs, {required this.evenOdd});
  final List<PathSeg> segs;
  final bool evenOdd;
}

/// A region drawing is held inside: the intersection of every path in it.
///
/// A PDF sets a clip with `W` and keeps it until the graphics state it was
/// set in is restored, and each new one narrows the last, so a region is
/// its parent's paths with one more.
class PageClip {
  const PageClip(this.paths);
  final List<ClipPath> paths;
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
    this.clip = kNoClip,
    this.blend = PdfBlend.normal,
  });
  final List<PathSeg> segs;
  final bool fill, stroke, evenOdd;
  final int fillColor, strokeColor;
  final double lineWidth;
  final int seq;
  final int clip;

  /// How the path mixes with what is under it, from the /BM of an
  /// /ExtGState: a highlight is usually multiplied, so the words stay dark.
  final PdfBlend blend;
}

/// The blend modes a PDF names, in the order ISO 32000 lists them.
enum PdfBlend {
  normal,
  multiply,
  screen,
  overlay,
  darken,
  lighten,
  colorDodge,
  colorBurn,
  hardLight,
  softLight,
  difference,
  exclusion,
  hue,
  saturation,
  color,
  luminosity;

  /// The mode named [name] in a file, or null for one it does not know.
  static PdfBlend? named(String name) => switch (name) {
        'Normal' || 'Compatible' => normal,
        'Multiply' => multiply,
        'Screen' => screen,
        'Overlay' => overlay,
        'Darken' => darken,
        'Lighten' => lighten,
        'ColorDodge' => colorDodge,
        'ColorBurn' => colorBurn,
        'HardLight' => hardLight,
        'SoftLight' => softLight,
        'Difference' => difference,
        'Exclusion' => exclusion,
        'Hue' => hue,
        'Saturation' => saturation,
        'Color' => color,
        'Luminosity' => luminosity,
        _ => null,
      };
}

/// A smooth shading: an axial or radial blend of [colors], evenly spread
/// along its parameter, drawn over the whole of its clip region.
class ShadeCmd {
  ShadeCmd({
    required this.radial,
    required this.coords,
    required this.matrix,
    required this.colors,
    required this.extendStart,
    required this.extendEnd,
    required this.seq,
    this.clip = kNoClip,
  });

  final bool radial;

  /// x0 y0 x1 y1, or x0 y0 r0 x1 y1 r1 when [radial], in the shading's own
  /// space, which [matrix] takes to top-left page space.
  final List<double> coords;
  final Mat matrix;
  final List<int> colors;
  final bool extendStart, extendEnd;
  final int seq;
  final int clip;
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
    this.clip = kNoClip,
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
  final int clip;

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
  final List<ShadeCmd> shades = [];

  /// Every clip region a command refers to by index.
  final List<PageClip> clips = [];

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
      this.color, this.seq, {this.angle = 0, this.clip = kNoClip});

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

  /// The direction the baseline runs, in radians clockwise. The painter turns
  /// the line about its origin by this much.
  final double angle;

  /// The clip region the line is drawn inside. Runs in different regions are
  /// never merged into one line.
  final int clip;

  bool get bold => (style & 1) != 0;
  bool get italic => (style & 2) != 0;
  bool get serif => (style & 4) != 0;
  bool get mono => (style & 8) != 0;

  /// The box this line paints into, in top-left page space.
  ///
  /// The painter draws from `y - size * 0.8`, so a highlight drawn over this
  /// rect covers exactly the glyphs and not the line above.
  Rect get bounds {
    final upright = Rect.fromLTWH(x, y - size * 0.8, width, size);
    if (angle == 0) return upright;
    final cos = math.cos(angle), sin = math.sin(angle);
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    for (final (dx, dy) in [(0.0, -size * 0.8), (width, -size * 0.8),
        (0.0, size * 0.2), (width, size * 0.2)]) {
      final px = x + dx * cos - dy * sin;
      final py = y + dx * sin + dy * cos;
      l = math.min(l, px);
      t = math.min(t, py);
      r = math.max(r, px);
      b = math.max(b, py);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// The box around characters [start] to [end] of [text], interpolated across
  /// [width]. Glyph-exact positions are gone by merge time, and a proportional
  /// slice is what lets a match be highlighted without re-running the page.
  Rect sliceBounds(int start, int end) {
    if (text.isEmpty || width <= 0 || angle != 0) return bounds;
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
/// not by taste. It was swept on fonts whose space is about Helvetica's, so a
/// run that knows its font's space scales it by how that space compares: a
/// monospace face needs a wider gap before it means a word break, and a
/// condensed one a narrower gap.
///
/// Turned runs cannot share a baseline with the upright page, so they are
/// joined only to the run that carries on from where they end, in the order
/// the file drew them, and come after the upright lines.
List<LaidOutRun> mergeRuns(List<TextRunCmd> runs,
    {double wordGapEm = kWordGapEm}) {
  if (runs.isEmpty) return const [];
  final upright = <TextRunCmd>[];
  final turned = <TextRunCmd>[];
  for (final r in runs) {
    (r.rotated ? turned : upright).add(r);
  }
  return [
    ..._mergeUpright(upright, wordGapEm),
    ..._mergeTurned(turned, wordGapEm),
  ];
}

/// Helvetica's space, in ems, which is what [kWordGapEm] was swept against.
const double _referenceSpaceEm = 0.278;

double _gapFor(TextRunCmd r, double size, double wordGapEm) {
  final base = size * wordGapEm;
  if (r.spaceWidthPts <= 0 || r.fontSize <= 0) return base;
  final ratio = (r.spaceWidthPts / r.fontSize) / _referenceSpaceEm;
  return base * ratio.clamp(0.5, 2.5);
}

List<LaidOutRun> _mergeUpright(List<TextRunCmd> runs, double wordGapEm) {
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
  var clip = sorted.first.clip;

  void flush(double endX) {
    final s = buf.toString();
    if (s.trim().isNotEmpty) {
      out.add(LaidOutRun(
          s, startX, lineY, size, endX - startX, style, color, seq,
          clip: clip));
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
        r.color == color &&
        r.clip == clip;
    final gap = r.x - cursor;
    if (sameLine && sameStyle && gap > -size * 0.6 && gap < size * 1.2) {
      // A gap this wide is a word break the producer expressed as positioning
      // rather than as a space glyph.
      if (gap > _gapFor(r, size, wordGapEm) && !buf.toString().endsWith(' ')) {
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
    clip = r.clip;
    buf.write(r.text);
    cursor = r.x + r.widthPts;
  }
  flush(cursor);
  return out;
}

List<LaidOutRun> _mergeTurned(List<TextRunCmd> runs, double wordGapEm) {
  if (runs.isEmpty) return const [];
  final sorted = List<TextRunCmd>.from(runs)
    ..sort((a, b) => a.seq.compareTo(b.seq));
  final out = <LaidOutRun>[];
  TextRunCmd? head;
  var buf = StringBuffer();
  var length = 0.0;
  var endX = 0.0, endY = 0.0;

  void flush() {
    final h = head;
    if (h != null && buf.toString().trim().isNotEmpty) {
      out.add(LaidOutRun(buf.toString(), h.x, h.y, h.fontSize, length,
          _styleOf(h), h.color, h.seq,
          angle: h.angle, clip: h.clip));
    }
    head = null;
    buf = StringBuffer();
  }

  for (final r in sorted) {
    final h = head;
    if (h != null &&
        (r.angle - h.angle).abs() < 0.01 &&
        _styleOf(r) == _styleOf(h) &&
        (r.fontSize - h.fontSize).abs() < 0.6 &&
        r.color == h.color &&
        r.clip == h.clip) {
      final cos = math.cos(h.angle), sin = math.sin(h.angle);
      final dx = r.x - endX, dy = r.y - endY;
      final along = dx * cos + dy * sin;
      final across = -dx * sin + dy * cos;
      if (across.abs() <= h.fontSize * 0.3 &&
          along > -h.fontSize * 0.6 &&
          along < h.fontSize * 1.2) {
        if (along > _gapFor(r, h.fontSize, wordGapEm) &&
            !buf.toString().endsWith(' ')) {
          buf.write(' ');
        }
        buf.write(r.text);
        length += along + r.widthPts;
        endX = r.x + r.widthPts * cos;
        endY = r.y + r.widthPts * sin;
        continue;
      }
    }
    flush();
    head = r;
    buf.write(r.text);
    length = r.widthPts;
    endX = r.x + r.widthPts * math.cos(r.angle);
    endY = r.y + r.widthPts * math.sin(r.angle);
  }
  flush();
  return out;
}
