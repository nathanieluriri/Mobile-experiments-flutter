import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../theme/colors.dart';

/// The loop's outside measure. Every other number here is derived from it, so
/// a caller that reserves this much room can never have the wave paint outside
/// the box it was given.
const double kSpinnerSize = 48.0;

/// How thick the loop is drawn.
const double kSpinnerStroke = 3.5;

/// How far round the loop travels, in degrees.
///
/// The missing sixty degrees are the whole of what makes the turn legible: a
/// closed ring rotating is a ring standing still, and an indicator nobody can
/// see moving is worse than no indicator at all.
const double kSpinnerSweep = 300.0;

/// One full turn.
const Duration kSpinnerPeriod = Duration(milliseconds: 1100);

/// How far the radius travels either side of its mean.
const double kSpinnerWave = 2.5;

/// How many crests fit into the sweep.
///
/// A whole number, so the wave meets itself where the arc begins and ends and
/// neither tip is a step. Nine is what turns a progress ring into something
/// that looks drawn by hand: few enough that each crest is a shape rather than
/// a texture, many enough that no crest reads as the top of the loop.
const int kSpinnerWaveCycles = 9;

/// How many crests one full turn carries past a fixed point on the screen.
///
/// It is not a free number: the arc's rotation and the wave's own travel run
/// against each other, and this is what the two come to. It exists so a test
/// can state the travel rather than measure a picture of it.
const double kSpinnerCrestsPerTurn =
    kSpinnerWaveCycles * 360.0 / kSpinnerSweep - 1;

/// How many straight segments the wave is drawn with: twenty four a crest,
/// which is past the point where a longer path changes a pixel.
const int kSpinnerSegments = kSpinnerWaveCycles * 24;

/// Where the loop starts when it has made no turn at all: the top of the box.
const double kSpinnerStartAngle = -math.pi / 2;

/// The wavering loop that says the app is busy.
///
/// It is the only indeterminate indicator in quire, and it earns that by not
/// pretending to measure anything. A smooth ring invites a reader to look for
/// how far round it has gone; a hand drawn loop that will not hold still says
/// plainly that nobody knows yet, which is the truth of a file being opened.
///
/// [turns] carries the whole animation. Passing a controller's value rather
/// than reading a clock is what lets a test hold this at 275 ms and photograph
/// it.
/// How long the crinkle takes to travel once round the ring.
const Duration kSpinnerTrace = Duration(milliseconds: 700);

class SpinnerPainter extends CustomPainter {
  const SpinnerPainter({
    required this.turns,
    this.color = AppColors.accentBright,
    this.arc = 1,
    this.trace = 1,
  });

  /// How far round the loop has gone, in turns. Only the fraction shows.
  final double turns;

  final Color color;

  /// How much of the ring is drawn at all, 0 to 1. A pull draws the ring on
  /// as it goes, so the loop is a readout of the pull before it is a loop.
  final double arc;

  /// How far round the ring the crinkle has travelled, 0 for a plain circle
  /// and 1 for the whole ring in the zig zag it works in.
  ///
  /// It is a front rather than a depth: the wave is at its full height behind
  /// it and flat in front of it, so the shape is drawn into being rather than
  /// swelling everywhere at once, which is what makes it read as one line
  /// being traced.
  final double trace;

  /// The mean radius inside [size]: the largest that keeps both the stroke's
  /// half width and the wave's crest inside the box.
  static double meanRadius(Size size) =>
      math.min(size.width, size.height) / 2 - kSpinnerStroke / 2 - kSpinnerWave;

  /// Where the loop's stroke runs at [u], nought at the arc's tail and one at
  /// its head, for a loop of [turns] centred on [centre] at [mean] radius.
  ///
  /// The wave's phase advances with the rotation, which is what sends the
  /// squiggle travelling round the loop instead of turning with it. A wave
  /// pinned to the arc would rotate rigidly and read as a printed shape being
  /// spun, not as a line being drawn.
  static Offset pointAt(
    double u,
    double turns,
    Offset centre,
    double mean, {
    double trace = 1,
  }) {
    final phase = turns * 2 * math.pi;
    final angle =
        kSpinnerStartAngle + phase + kSpinnerSweep * math.pi / 180 * u;
    // Full height behind the front, nothing in front of it, over a short
    // shoulder so the line is never kinked where the two meet. Once the front
    // has been all the way round, the ring is the shape it works in and the
    // front is not in it anywhere.
    final height = trace >= 1 ? 1.0 : ((trace - u) * 4).clamp(0.0, 1.0);
    final radius =
        mean +
        kSpinnerWave *
            height *
            math.sin(kSpinnerWaveCycles * 2 * math.pi * u + phase);
    return centre + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final mean = meanRadius(size);
    if (mean <= 0) return;
    final drawn = arc.clamp(0.0, 1.0);
    if (drawn <= 0) return;
    final path = Path();
    for (var i = 0; i <= kSpinnerSegments; i++) {
      final point = pointAt(
        i / kSpinnerSegments * drawn,
        turns,
        centre,
        mean,
        trace: trace,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = kSpinnerStroke
        // Round, because the two tips are where a reader looks to see the
        // loop move, and a mitred tip on a wave lands as a splinter.
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SpinnerPainter old) =>
      old.turns != turns ||
      old.color != color ||
      old.arc != arc ||
      old.trace != trace;
}
