import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/physics.dart';

import '../theme/easings.dart';
import '../theme/springs.dart';
import 'arrival_geometry.dart';
import 'quire_mark.dart';

/// How long the reveal takes, from the resting mark to the live desk.
const kArrivalReveal = Duration(milliseconds: 1100);

/// When the window starts to swell past the screen, in milliseconds.
const kArrivalSwellFrom = 420.0;

/// How far into the swell the window has passed every corner of the screen.
/// The rest of the swell happens where nobody can see it, so the arrival can
/// be taken away at the end without a pixel changing.
const kArrivalCovered = 0.86;

/// How far the desk stands forward while the mark is still over it.
const kArrivalDeskScale = 1.05;

/// One frame of the reveal. Lengths are in the mark's own units unless their
/// name says otherwise.
class ArrivalPose {
  const ArrivalPose({
    required this.nameOpacity,
    required this.nameDrop,
    required this.exactMark,
    required this.window,
    required this.swell,
    required this.gooOutline,
    required this.gooHole,
    required this.rim,
    required this.morph,
    required this.panes,
    required this.blob,
    required this.blobCorner,
    required this.tension,
    required this.stubRound,
    required this.flapMelt,
    required this.deskScale,
  });

  /// The pose the native splash hands over.
  static const rest = ArrivalPose(
    nameOpacity: 1,
    nameDrop: 0,
    exactMark: 1,
    window: 0,
    swell: 1,
    gooOutline: 0,
    gooHole: 0,
    rim: 0,
    morph: 0,
    panes: [PanePose.rest, PanePose.rest, PanePose.rest, PanePose.rest],
    blob: Rect.zero,
    blobCorner: 0,
    tension: 0,
    stubRound: 0,
    flapMelt: 0,
    deskScale: kArrivalDeskScale,
  );

  /// The pose once the window has passed every edge of the screen.
  static const gone = ArrivalPose(
    nameOpacity: 0,
    nameDrop: 0,
    exactMark: 0,
    window: 1,
    swell: 1,
    gooOutline: 0,
    gooHole: 0,
    rim: 0,
    morph: 0,
    panes: [PanePose.rest, PanePose.rest, PanePose.rest, PanePose.rest],
    blob: Rect.zero,
    blobCorner: 0,
    tension: 0,
    stubRound: 0,
    flapMelt: 0,
    deskScale: 1,
  );

  final double nameOpacity;

  /// How far the name has sunk, in logical pixels.
  final double nameDrop;

  /// How much of the vector mark still lies over the goo.
  final double exactMark;

  /// How much of the desk shows through the holes.
  final double window;

  /// The whole mark's scale about [QuireMark.middle].
  final double swell;

  /// How far apart two outlines, and two holes, can be and still flow
  /// together.
  final double gooOutline;
  final double gooHole;

  /// The rim's width, and how far the frame has become that rim.
  final double rim;
  final double morph;

  final List<PanePose> panes;

  /// The one soft window the holes are pulled into, its corner radius as a
  /// share of its half width, and how much of its size it has grown to from
  /// the middle of the mark.
  final Rect blob;
  final double blobCorner;
  final double tension;

  /// How rounded the ends of the bars are as they part and draw back.
  final double stubRound;

  /// How far the dog ear has melted down into its pane.
  final double flapMelt;

  /// The desk's scale behind the window, about the centre of the screen.
  final double deskScale;
}

/// Where one pane has gone.
class PanePose {
  const PanePose({
    required this.shift,
    required this.outlineScale,
    required this.holeScale,
    required this.outlineRound,
    required this.holeRound,
  });

  static const rest = PanePose(
    shift: Offset.zero,
    outlineScale: 1,
    holeScale: 1,
    outlineRound: 0,
    holeRound: 0,
  );

  final Offset shift;

  /// The outline's scale about the pane's centre.
  final double outlineScale;

  /// Each hole's scale about its own centre.
  final double holeScale;

  /// How far the outline's and the holes' corners have softened.
  final double outlineRound;
  final double holeRound;
}

/// The reveal at [ms] milliseconds in, on a screen of [size].
ArrivalPose arrivalPoseAt(double ms, ArrivalGeometry geometry, Size size) {
  if (ms <= 0) return ArrivalPose.rest;
  final end = kArrivalReveal.inMilliseconds.toDouble();
  if (ms >= end) return ArrivalPose.gone;

  final soften = easeInOutQuad.transform(_span(ms, 0, 320));
  final gather = _spring(AppSprings.gooRise, ms - 40);
  final panes = [
    for (var i = 0; i < 4; i++) _pane(i, ms, gather, soften),
  ];

  final wobble = ms <= _wobbleFrom
      ? 0.0
      : _wobbleDepth *
            math.exp(-(ms - _wobbleFrom) / _wobbleDecay) *
            math.sin(2 * math.pi * (ms - _wobbleFrom) / _wobblePeriod);
  final blob = Rect.fromCenter(
    center: QuireMark.middle,
    width: 2 * _blobHalf * (1 + wobble),
    height: 2 * _blobHalf * (1 - wobble),
  );

  final swellAt = _span(ms, kArrivalSwellFrom, end);
  final cover = _coveringSwell(geometry, size);
  final growth = math.exp(
    math.log(cover) * math.pow(swellAt / kArrivalCovered, 2),
  );
  final rimDp = _rimFrom + (_rimTo - _rimFrom) * swellAt * swellAt;

  return ArrivalPose(
    nameOpacity: 1 - easeInOutQuad.transform(_span(ms, 0, 220)),
    nameDrop: 10 * easeInOutQuad.transform(_span(ms, 0, 220)),
    exactMark: 1 - _span(ms, 0, 90),
    window: easeOutCubic.transform(_span(ms, 20, 240)),
    swell: growth,
    gooOutline: 8 * easeInOutQuad.transform(_span(ms, 40, 320)),
    gooHole: 6 * easeInOutQuad.transform(_span(ms, 160, 420)),
    rim: rimDp / (geometry.unit * growth),
    morph: easeInOutCubic.transform(_span(ms, 300, 620)),
    panes: panes,
    blob: blob,
    blobCorner: _blobCorner,
    tension: easeOutCubic.transform(_span(ms, 300, 620)),
    stubRound: 8,
    flapMelt: easeInOutCubic.transform(_span(ms, 60, 380)),
    deskScale:
        1 +
        (kArrivalDeskScale - 1) *
            (1 - easeOutCubic.transform(_span(ms, 240, end))),
  );
}

const _stagger = [0.0, 40.0, 70.0, 100.0];
const _holeOpen = 1.22;
const _outlineRound = 9.0;
const _holeRound = 7.0;
const _rimRest = 7.57;
const _rimFrom = 6.0;
const _rimTo = 2.0;
const _wobbleFrom = 560.0;
const _wobbleDepth = 0.07;
const _wobbleDecay = 140.0;
const _wobblePeriod = 300.0;

/// The gaps between the panes, which gathering closes.
const _gapAcross = 5.18;
const _gapDown = 3.16;

/// The soft window the four holes settle into: as wide as they are once they
/// have opened and gathered, with corners rounded to a little under half its
/// width.
final _blobHalf =
    (QuireMark.middle.dx - QuireMark.panes[0].centre.dx) +
    QuireMark.panes[0].holes.last.getBounds().width / 2 * _holeOpen;
const _blobCorner = 0.46;

PanePose _pane(int i, double ms, double gather, double soften) {
  final pane = QuireMark.panes[i];
  final open = _spring(AppSprings.gooSpread, ms - 140 - _stagger[i]);
  final hole = 1 + (_holeOpen - 1) * open;
  final holeSize = pane.holes.last.getBounds().width;
  return PanePose(
    shift: _towardMiddle(i) * gather,
    outlineScale: (holeSize * hole + 2 * _rimRest) / pane.square.width,
    holeScale: hole,
    outlineRound: _outlineRound * soften,
    holeRound: _holeRound * soften,
  );
}

Offset _towardMiddle(int i) {
  final toward = QuireMark.middle - QuireMark.panes[i].centre;
  return Offset(
    toward.dx.sign * _gapAcross / 2,
    toward.dy.sign * _gapDown / 2,
  );
}

double _span(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

/// A spring from 0 to 1 released at time 0, [ms] later.
double _spring(SpringDescription spring, double ms) {
  if (ms <= 0) return 0;
  return SpringSimulation(spring, 0, 1, 0).x(ms / 1000);
}

/// The swell at which the settled window passes every corner of the screen.
double _coveringSwell(ArrivalGeometry geometry, Size size) {
  final centre = geometry.place(QuireMark.middle);
  var needed = 1.0;
  for (final corner in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ]) {
    final to = corner - centre;
    final reach = to.distance;
    if (reach == 0) continue;
    final edge = blobEdgeAlong(to / reach) * geometry.unit;
    needed = math.max(needed, reach / edge);
  }
  return needed * 1.02;
}

/// How far the settled window's edge is from its centre along [direction], in
/// the mark's units.
double blobEdgeAlong(Offset direction) {
  var t = 0.0;
  for (var i = 0; i < 64; i++) {
    final d = _roundBox(direction * t, _blobHalf, _blobHalf * _blobCorner);
    if (d.abs() < 1e-6) break;
    t -= d;
  }
  return t;
}

double _roundBox(Offset p, double half, double radius) {
  final qx = p.dx.abs() - half + radius;
  final qy = p.dy.abs() - half + radius;
  final outside = math.sqrt(
    math.pow(math.max(qx, 0.0), 2) + math.pow(math.max(qy, 0.0), 2),
  );
  return outside + math.min(math.max(qx, qy), 0.0) - radius;
}
