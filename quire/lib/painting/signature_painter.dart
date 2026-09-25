import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:flutter/rendering.dart';

import '../helpers/catmull_rom.dart';
import '../services/document_store.dart';
import '../theme/colors.dart';

export '../helpers/catmull_rom.dart' show kResampleStep, kStrokeTension;

/// How wide a stroke is where the hand has almost stopped.
const kInkWidthSlow = 4.2;

/// How wide it is at [kInkSpeedCeiling] and above.
const kInkWidthFast = 1.2;

/// The speed, in points per second, at which a stroke reaches its thinnest.
const kInkSpeedCeiling = 2000.0;

/// How many samples the speed is averaged over.
///
/// A raw touch stream stutters, and an unsmoothed width follows every stutter,
/// which reads as a rope rather than as ink. Four samples is enough to settle
/// it and short enough that a real change of hand still shows.
const kInkSpeedWindow = 4;

/// The alpha a stroke is laid down at, and the alpha it dries to.
const kInkWetAlpha = 0x99;
const kInkDryAlpha = 0xFF;

/// The halo under a wet stroke: its alpha, its blur, and how far it spreads
/// as the stroke dries.
const kInkBleedAlpha = 0x14;
const kInkBleedSigma = 2.0;
const kInkBleedSpread = 1.06;

/// How opaque a mark is once it is part of the page.
const kPlacedInkAlpha = 0.92;

/// How many segments a round cap is drawn from.
const kInkCapSteps = 8;

/// One stroke of a signature: an evenly spaced centre line and the half width
/// of the ribbon at each of its points.
///
/// The width is not a style, it is a recording. It comes from how fast the
/// hand was moving, which is why a flourish is thin and a deliberate
/// downstroke is fat, and why the same stroke replayed is the same shape to
/// the last point.
class InkStroke {
  InkStroke(this.centre, this.halfWidths)
    : assert(centre.length == halfWidths.length, 'a width for every point');

  /// Builds a stroke from the raw pointer [samples] and the [times] they
  /// arrived at.
  ///
  /// Timestamps come from the events rather than from a clock read here, so a
  /// scripted gesture with written timestamps produces byte identical ink.
  factory InkStroke.fromSamples(List<Offset> samples, List<Duration> times) {
    if (samples.isEmpty) return InkStroke(const <Offset>[], const <double>[]);
    final rawHalf = _halfWidthsOf(samples, times);
    if (samples.length == 1) {
      return InkStroke(<Offset>[samples.first], <double>[rawHalf.first]);
    }
    final centre = resampleStroke(samples);
    return InkStroke(centre, _spreadOver(centre, samples, rawHalf));
  }

  /// The resampled centre line, one point every [kResampleStep].
  final List<Offset> centre;

  /// Half the ribbon's width at each point of [centre].
  final List<double> halfWidths;

  Path? _path;
  List<Offset>? _outline;

  bool get isEmpty => centre.isEmpty;

  /// The ink's own box, the ribbon's width included.
  Rect get bounds {
    if (isEmpty) return Rect.zero;
    var box = Rect.fromCircle(center: centre.first, radius: halfWidths.first);
    for (var i = 1; i < centre.length; i++) {
      box = box.expandToInclude(
        Rect.fromCircle(center: centre[i], radius: halfWidths[i]),
      );
    }
    return box;
  }

  /// The ribbon as one closed polygon: up one side, round the far cap, back
  /// down the other, round the near cap, and closed.
  ///
  /// A polygon rather than a stroked line because a stroked line has one
  /// width, and because a polygon survives being stored, scaled and redrawn
  /// with no record of the hand that made it.
  List<Offset> outline() => _outline ??= _buildOutline();

  /// The same ribbon as a fillable path.
  Path path() => _path ??= (Path()
    ..fillType = PathFillType.nonZero
    ..addPolygon(outline(), true));

  List<Offset> _buildOutline() {
    if (isEmpty) return const <Offset>[];
    if (centre.length == 1) {
      return _arc(centre.first, halfWidths.first, 0, 2 * math.pi, closed: true);
    }
    final normals = <Offset>[
      for (var i = 0; i < centre.length; i++) _normalAt(i),
    ];
    final out = <Offset>[];
    for (var i = 0; i < centre.length; i++) {
      out.add(centre[i] + normals[i] * halfWidths[i]);
    }
    out.addAll(_cap(centre.last, normals.last, halfWidths.last));
    for (var i = centre.length - 1; i >= 0; i--) {
      out.add(centre[i] - normals[i] * halfWidths[i]);
    }
    out.addAll(_cap(centre.first, -normals.first, halfWidths.first));
    out.add(out.first);
    return out;
  }

  /// The unit normal at point [i], taken from the line through its
  /// neighbours so a corner is not mitred out into a needle.
  Offset _normalAt(int i) {
    final before = centre[math.max(i - 1, 0)];
    final after = centre[math.min(i + 1, centre.length - 1)];
    final tangent = after - before;
    final length = tangent.distance;
    if (length == 0) return const Offset(0, -1);
    return Offset(-tangent.dy / length, tangent.dx / length);
  }

  /// The interior points of the round cap at [at], sweeping from the [normal]
  /// side to the other one.
  List<Offset> _cap(Offset at, Offset normal, double radius) {
    final from = math.atan2(normal.dy, normal.dx);
    return _arc(at, radius, from, from + math.pi).sublist(1, kInkCapSteps);
  }

  List<Offset> _arc(
    Offset at,
    double radius,
    double from,
    double to, {
    bool closed = false,
  }) {
    final points = <Offset>[
      for (var i = 0; i <= kInkCapSteps; i++)
        at +
            Offset(
              math.cos(from + (to - from) * i / kInkCapSteps),
              math.sin(from + (to - from) * i / kInkCapSteps),
            ) *
                radius,
    ];
    if (closed) points.add(points.first);
    return points;
  }
}

/// Half the ribbon's width at every raw sample, from the smoothed speed.
List<double> _halfWidthsOf(List<Offset> samples, List<Duration> times) {
  final speeds = List<double>.filled(samples.length, 0);
  for (var i = 1; i < samples.length; i++) {
    final seconds =
        (times[math.min(i, times.length - 1)] -
                times[math.min(i - 1, times.length - 1)])
            .inMicroseconds /
        Duration.microsecondsPerSecond;
    // Two samples stamped at the same instant say nothing about speed, so the
    // hand is taken to be doing what it was doing.
    speeds[i] = seconds > 0
        ? (samples[i] - samples[i - 1]).distance / seconds
        : speeds[i - 1];
  }
  if (samples.length > 1) speeds[0] = speeds[1];
  return <double>[
    for (var i = 0; i < speeds.length; i++) _halfWidthAt(_mean(speeds, i)),
  ];
}

/// The trailing mean of the last [kInkSpeedWindow] speeds up to [i].
double _mean(List<double> speeds, int i) {
  final from = math.max(0, i - kInkSpeedWindow + 1);
  var total = 0.0;
  for (var k = from; k <= i; k++) {
    total += speeds[k];
  }
  return total / (i - from + 1);
}

double _halfWidthAt(double speed) =>
    lerpDouble(
      kInkWidthSlow,
      kInkWidthFast,
      (speed / kInkSpeedCeiling).clamp(0.0, 1.0),
    )! /
    2;

/// Carries the widths recorded at [samples] onto the evenly spaced [centre].
///
/// Both lines walk the same stroke, so a point is matched by how far along it
/// sits rather than by index: the resampled line has more points than the raw
/// one, and they are not the same points.
List<double> _spreadOver(
  List<Offset> centre,
  List<Offset> samples,
  List<double> rawHalf,
) {
  final walked = <double>[0];
  for (var i = 1; i < samples.length; i++) {
    walked.add(walked.last + (samples[i] - samples[i - 1]).distance);
  }
  final total = walked.last;
  if (total <= 0) {
    return List<double>.filled(centre.length, rawHalf.first);
  }
  final out = <double>[];
  var k = 0;
  for (var j = 0; j < centre.length; j++) {
    final along = centre.length == 1 ? 0.0 : total * j / (centre.length - 1);
    while (k < walked.length - 2 && walked[k + 1] < along) {
      k++;
    }
    final span = walked[k + 1] - walked[k];
    final t = span <= 0 ? 0.0 : ((along - walked[k]) / span).clamp(0.0, 1.0);
    out.add(lerpDouble(rawHalf[k], rawHalf[k + 1], t)!);
  }
  return out;
}

/// A finished signature: every stroke's ribbon as a polygon in the unit square
/// of the whole mark.
///
/// Storing outlines rather than centre lines and speeds is what lets a mark be
/// put on a page at any size and reread later with no record of the gesture
/// that drew it. The shape is the signature; the hand is not kept.
class SignatureMark {
  const SignatureMark(this.outlines, this.bounds, {this.picture, this.encoded});

  /// A mark the reader brought in rather than drew.
  ///
  /// A photograph of a signature on paper is a signature, and asking somebody
  /// to draw theirs again with a fingertip when they already have a good one
  /// is asking them for a worse one. It is held as both: the decoded picture
  /// to draw, and the bytes it came in as, which are what get written down
  /// and what go into the PDF.
  factory SignatureMark.picture(ui.Image picture, Uint8List encoded) =>
      SignatureMark(
        const <List<Offset>>[],
        Rect.fromLTWH(0, 0, picture.width.toDouble(), picture.height.toDouble()),
        picture: picture,
        encoded: encoded,
      );

  /// Builds the mark [strokes] make together.
  factory SignatureMark.of(List<InkStroke> strokes) {
    final drawn = strokes.where((s) => !s.isEmpty).toList();
    if (drawn.isEmpty) {
      return const SignatureMark(<List<Offset>>[], Rect.zero);
    }
    var box = drawn.first.bounds;
    for (final stroke in drawn.skip(1)) {
      box = box.expandToInclude(stroke.bounds);
    }
    final width = box.width == 0 ? 1.0 : box.width;
    final height = box.height == 0 ? 1.0 : box.height;
    return SignatureMark(<List<Offset>>[
      for (final stroke in drawn)
        <Offset>[
          for (final point in stroke.outline())
            Offset((point.dx - box.left) / width, (point.dy - box.top) / height),
        ],
    ], box);
  }

  /// Each stroke's ribbon, in the unit square of [bounds].
  final List<List<Offset>> outlines;

  /// The box the mark was drawn in, which is what the unit square stands for.
  final Rect bounds;

  /// The picture, for a mark that is one, ready to be drawn.
  final ui.Image? picture;

  /// The file that picture came in as, for writing down and for the PDF.
  final Uint8List? encoded;

  bool get isEmpty => picture == null && outlines.isEmpty;

  /// Height over width, so a stamp of a given width knows how tall it is.
  double get aspect =>
      bounds.width == 0 ? 1 : bounds.height / bounds.width;

  /// The mark drawn to fill [box].
  Path pathIn(Rect box) => pathOf(outlines, box);

  /// Draws whichever kind of mark this is into [box] at [alpha].
  ///
  /// A drawn mark is filled in the page's own ink and multiplied into the
  /// print under it. A picture is drawn as it is: it carries its own colour,
  /// and a photograph of blue biro should stay blue biro.
  void paintInto(Canvas canvas, Rect box, {double alpha = 1}) {
    final image = picture;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        box,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
      );
      return;
    }
    canvas.drawPath(
      pathIn(box),
      Paint()..color = AppColors.pageInk.withValues(alpha: alpha),
    );
  }

  /// The same, for outlines that have already been stored on a page.
  static Path pathOf(List<List<Offset>> outlines, Rect box) {
    final path = Path()..fillType = PathFillType.nonZero;
    for (final outline in outlines) {
      if (outline.length < 3) continue;
      path.addPolygon(<Offset>[
        for (final point in outline)
          Offset(box.left + point.dx * box.width, box.top + point.dy * box.height),
      ], true);
    }
    return path;
  }
}

/// Paints the strokes on the pad, with the newest one still drying.
///
/// [dry] is already eased by the controller that drives it, so this is a
/// straight interpolation: the alpha climbs from wet to dry while the bleed
/// under it spreads and leaves.
class SignaturePainter extends CustomPainter {
  const SignaturePainter({
    required this.strokes,
    required this.dry,
    this.color = AppColors.pageInk,
  });

  final List<InkStroke> strokes;

  /// 0 the moment the newest stroke ended, 1 once it has set.
  final double dry;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (stroke.isEmpty) continue;
      final wetness = i == strokes.length - 1 ? dry.clamp(0.0, 1.0) : 1.0;
      final path = stroke.path();
      if (wetness < 1) _bleed(canvas, path, wetness);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withAlpha(
            lerpDouble(kInkWetAlpha, kInkDryAlpha, wetness)!.round(),
          ),
      );
    }
  }

  /// The halo wet ink pushes into paper: the same polygon, blurred, spreading
  /// as it is drawn away into the fibre.
  void _bleed(Canvas canvas, Path path, double wetness) {
    final centre = path.getBounds().center;
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(lerpDouble(1, kInkBleedSpread, wetness)!);
    canvas.translate(-centre.dx, -centre.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withAlpha((kInkBleedAlpha * (1 - wetness)).round())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, kInkBleedSigma),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SignaturePainter old) =>
      old.dry != dry || old.strokes != strokes || old.color != color;
}

/// Paints the marks that are already part of a page.
///
/// Multiply rather than source over, so where a signature crosses printed text
/// it darkens instead of covering, which is what wet ink over toner does.
class PlacedInkPainter extends CustomPainter {
  const PlacedInkPainter({
    required this.signatures,
    required this.pageIndex,
    required this.pageSize,
  });

  final List<PlacedSignature> signatures;

  /// Which page is being painted. A mark belongs to one page and no other.
  final int pageIndex;

  /// The page's own size in points, which is what a mark's rect is stated in.
  final Size pageSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (pageSize.width <= 0) return;
    final scale = size.width / pageSize.width;
    for (final mark in signatures) {
      if (mark.pageIndex != pageIndex) continue;
      final box = Rect.fromLTWH(
        mark.rect.left * scale,
        mark.rect.top * scale,
        mark.rect.width * scale,
        mark.rect.height * scale,
      );
      final picture = mark.picture;
      if (picture != null) {
        canvas.drawImageRect(
          picture,
          Rect.fromLTWH(
            0,
            0,
            picture.width.toDouble(),
            picture.height.toDouble(),
          ),
          box,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = BlendMode.multiply,
        );
        continue;
      }
      canvas.drawPath(
        SignatureMark.pathOf(mark.strokes, box),
        Paint()
          ..color = AppColors.pageInk.withValues(alpha: kPlacedInkAlpha)
          ..blendMode = BlendMode.multiply,
      );
    }
  }

  @override
  bool shouldRepaint(PlacedInkPainter old) {
    if (old.pageIndex != pageIndex || old.pageSize != pageSize) return true;
    if (old.signatures.length != signatures.length) return true;
    // The store hands out a fresh list every read, so the marks themselves are
    // what has to be compared, not the list holding them.
    for (var i = 0; i < signatures.length; i++) {
      if (!identical(old.signatures[i], signatures[i])) return true;
    }
    return false;
  }
}
