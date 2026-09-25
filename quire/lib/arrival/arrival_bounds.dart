import 'dart:math' as math;
import 'dart:ui';

import 'arrival_geometry.dart';
import 'arrival_motion.dart';
import 'quire_mark.dart';

// The shapes arrival.frag draws, as the boxes that hold them in the mark's own
// units before any pane is moved. Each is read off the constants in the
// shader, and has to change with them.
const _flapBox = Rect.fromLTRB(69.08, 60.5, 98.23, 94.0);
const _body0Box = Rect.fromLTRB(67.06, 75.64, 117.41, 125.99);
const _outlineBoxes = <Rect>[
  _body0Box,
  Rect.fromLTRB(122.59, 75.64, 172.94, 125.99),
  Rect.fromLTRB(67.06, 129.15, 117.41, 179.5),
  Rect.fromLTRB(122.59, 129.15, 172.94, 179.5),
];
const _flapHoleBox = Rect.fromLTRB(76.65, 68.07, 90.66, 82.21);
const _holeBoxes = <Rect>[
  Rect.fromLTRB(74.63, 83.21, 109.84, 118.42),
  Rect.fromLTRB(130.16, 83.21, 165.37, 118.42),
  Rect.fromLTRB(74.63, 136.72, 109.84, 171.93),
  Rect.fromLTRB(130.16, 136.72, 165.37, 171.93),
];
const _centres = <Offset>[
  Offset(92.235, 100.815),
  Offset(147.765, 100.815),
  Offset(92.235, 154.325),
  Offset(147.765, 154.325),
];
const _flapCentre = Offset(83.655, 75.14);
const _flapFoot = Offset(83.655, 86.0);
const _paneHalf = 17.605;
const _flapHalf = 7.005;
const _outlineHalf = 25.175;
const _outlineCorner = 5.05;
const _fingertip = 0.35;
const _fingerJoin = 1.5;
const _near = <Offset>[
  Offset(117.41 - _outlineCorner, 125.99 - _outlineCorner),
  Offset(122.59 + _outlineCorner, 125.99 - _outlineCorner),
  Offset(117.41 - _outlineCorner, 129.15 + _outlineCorner),
  Offset(122.59 + _outlineCorner, 129.15 + _outlineCorner),
];
const _inner = <Offset>[
  Offset(109.84, 118.42),
  Offset(130.16, 118.42),
  Offset(109.84, 136.72),
  Offset(130.16, 136.72),
];

/// Device pixels of ground kept round the bound. The shader measures an
/// edge's rate of change within three device pixels of it, so only past that
/// is its output the ground and nothing else.
const kArrivalBoundMargin = 5.0;

double _shrink(double s, double extent, double r) =>
    math.max(0.05, 1 - r / (s * extent));

Rect _scaledAbout(Rect box, Offset about, double s) => Rect.fromPoints(
  about + (box.topLeft - about) * s,
  about + (box.bottomRight - about) * s,
);

/// [box] of a shape scaled by [s] about [centre] and moved by anything from
/// [shiftFrom] to [shiftTo].
Rect _placed(
  Rect box,
  Offset centre,
  double s,
  Offset shiftFrom,
  Offset shiftTo,
) {
  final scaled = _scaledAbout(box, centre, s);
  return scaled.shift(shiftFrom).expandToInclude(scaled.shift(shiftTo));
}

Rect _segment(Offset a, Offset b, double radius) =>
    Rect.fromPoints(a, b).inflate(radius);

/// Where on the screen, in logical pixels, [pose] can draw anything but the
/// ground, or null when it may be anywhere.
///
/// Every distance the shader computes is at least the distance to the box of
/// the shape it measures, less what the smooth unions above it can take away,
/// which is a quarter of their width each. Outside the union of those boxes,
/// grown by that and by [kArrivalBoundMargin], every distance is past the
/// three device pixels the shader antialiases over, and its colour is the
/// ground exactly. So the painter runs the shader inside the bound only.
Rect? arrivalBounds(
  ArrivalPose pose,
  ArrivalGeometry geometry,
  double pixelRatio,
) {
  final middle = QuireMark.middle;
  final melt = 1 - 0.72 * pose.flapMelt;
  final boxes = <Rect>[];

  // The outlines, each moved by its shift times a zip anywhere from 1 to
  // 1 + zip, since the zip falls off with the distance from the middle.
  final z0 =
      1 + pose.zip * math.exp(-(_near[0] - middle).distanceSquared / 576.0);
  for (var i = 0; i < 4; i++) {
    final pane = pose.panes[i];
    final t = _shrink(pane.outlineScale, _outlineHalf, pane.outlineRound);
    final s = pane.outlineScale * t;
    var local = _outlineBoxes[i];
    var slack = 0.0;
    if (i == 0) {
      local = local.expandToInclude(_scaledAbout(_flapBox, _flapFoot, melt));
      slack = (6 * pose.flapMelt + pane.outlineRound) / 4;
    }
    boxes.add(
      _placed(
        local,
        _centres[i],
        s,
        pane.shift,
        pane.shift * (1 + pose.zip),
      ).inflate(slack * s + pane.outlineRound),
    );
    if (pose.join > 0) {
      final at = _centres[i] + (_near[i] - _centres[i]) * s + pane.shift * z0;
      final end = at + (middle - at) * pose.join;
      final r = _outlineCorner * s + pane.outlineRound;
      boxes.add(_segment(at, end, math.max(r, _fingertip)));
    }
  }
  final outlineSlack =
      pose.gooOutline / 2 + (pose.join > 0 ? _fingerJoin / 4 : 0);

  final holes = <Rect>[];
  final pane0 = pose.panes[0];
  final flapRound = pane0.holeRound * _flapHalf / _paneHalf;
  final sf = _shrink(pane0.holeScale, _flapHalf, flapRound);
  holes.add(
    _placed(
      _scaledAbout(_flapHoleBox, _flapFoot, melt),
      _flapCentre,
      pane0.holeScale * sf,
      pane0.shift,
      pane0.shift,
    ).inflate(flapRound),
  );
  for (var i = 0; i < 4; i++) {
    final pane = pose.panes[i];
    final t = _shrink(pane.holeScale, _paneHalf, pane.holeRound);
    final s = pane.holeScale * t;
    final slack = i == 0 ? pane.holeRound / 4 : 0.0;
    holes.add(
      _placed(
        _holeBoxes[i],
        _centres[i],
        s,
        pane.shift,
        pane.shift,
      ).inflate(slack * s + pane.holeRound),
    );
    if (pose.reach > 0) {
      final at = _centres[i] + (_inner[i] - _centres[i]) * s + pane.shift;
      final end = at + (middle - at) * pose.reach;
      holes.add(_segment(at, end, math.max(pane.holeRound, _fingertip)));
    }
  }
  if (pose.opening > 0) {
    holes.add(Rect.fromCircle(center: middle, radius: pose.opening));
  }
  if (pose.settle > 0) holes.add(pose.blob);
  final holeSlack =
      3 * pose.gooHole / 4 + (pose.opening > 0 ? pose.stubRound / 4 : 0);

  // The frame's edge is the holes grown by the rim once it has begun to be one.
  final rim = pose.morph > 0 ? math.max(pose.rim, 0.0) : 0.0;
  var scene = boxes
      .reduce((a, b) => a.expandToInclude(b))
      .inflate(outlineSlack);
  scene = scene.expandToInclude(
    holes.reduce((a, b) => a.expandToInclude(b)).inflate(holeSlack + rim),
  );
  if (!scene.isFinite) return null;

  Offset toScreen(Offset p) =>
      geometry.markBox.topLeft +
      (middle + (p - middle) * pose.swell) * geometry.unit;
  final screen = Rect.fromPoints(
    toScreen(scene.topLeft),
    toScreen(scene.bottomRight),
  ).inflate(kArrivalBoundMargin / pixelRatio);
  // Whole device pixels, so the edge of the shaded rect is never blended.
  return Rect.fromLTRB(
    (screen.left * pixelRatio).floorToDouble() / pixelRatio,
    (screen.top * pixelRatio).floorToDouble() / pixelRatio,
    (screen.right * pixelRatio).ceilToDouble() / pixelRatio,
    (screen.bottom * pixelRatio).ceilToDouble() / pixelRatio,
  );
}
