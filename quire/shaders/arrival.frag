#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The mark as signed distances, in the 240 unit viewport of
// quire_splash_icon.xml. Negative is inside.

uniform vec4 uFrame;   // mark origin x, y; logical px per unit; logical px per device px
uniform vec4 uGlobal;  // swell; window; goo between outlines; goo between holes
uniform vec2 uMiddle;  // where the panes gather, in units
uniform vec2 uRim;     // rim width in units; how far the frame has become a rim
uniform vec4 uPane0;   // shift x, shift y, outline scale, hole scale
uniform vec4 uPane1;
uniform vec4 uPane2;
uniform vec4 uPane3;
uniform vec4 uRound;   // how much each pane's holes have rounded, in units
uniform vec4 uSoft;    // how much each pane's outline has rounded, in units
uniform vec4 uBlob;    // the one window the holes settle into: centre x, y; half width, half height
uniform vec4 uTension; // its corners as a share of its half width; how far the holes have settled into it;
                       // how rounded the parted bars' ends are; how far the dog ear has melted
uniform vec4 uNeck;    // how far the outlines' and the holes' inner corners reach toward the middle;
                       // the opening there; how much harder the outlines are drawn together near it
uniform vec4 uGround;
uniform vec4 uInk;

out vec4 fragColor;

float segment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Distance to the quarter circle about c of radius r from its left to its top.
float topLeftArc(vec2 p, vec2 c, float r) {
  vec2 d = p - c;
  if (d.x <= 0.0 && d.y <= 0.0) return abs(length(d) - r);
  return min(length(d + vec2(r, 0.0)), length(d + vec2(0.0, r)));
}

// Distance to the quadratic from a through c to b, as four chords that stay
// within a thirtieth of a unit of it.
float bevel(vec2 p, vec2 a, vec2 c, vec2 b) {
  vec2 q1 = 0.5625 * a + 0.375 * c + 0.0625 * b;
  vec2 q2 = 0.25 * a + 0.5 * c + 0.25 * b;
  vec2 q3 = 0.0625 * a + 0.375 * c + 0.5625 * b;
  return min(
    min(segment(p, a, q1), segment(p, q1, q2)),
    min(segment(p, q2, q3), segment(p, q3, b))
  );
}

// Positive left of a side that runs straight down at x = b.x, bends along the
// quadratic from b through c to a, and runs on straight down at x = a.x.
// Along the curve x only grows as y shrinks, so the curve's x at p's height
// can be solved for directly.
float leftOf(vec2 p, vec2 a, vec2 c, vec2 b) {
  if (p.y >= a.y) return a.x - p.x;
  if (p.y <= b.y) return b.x - p.x;
  float qa = a.y - 2.0 * c.y + b.y;
  float qb = 2.0 * (c.y - a.y);
  float qc = a.y - p.y;
  float t = abs(qa) < 1e-5
      ? -qc / qb
      : (-qb - sqrt(max(qb * qb - 4.0 * qa * qc, 0.0))) / (2.0 * qa);
  t = clamp(t, 0.0, 1.0);
  float u = 1.0 - t;
  return u * u * a.x + 2.0 * u * t * c.x + t * t * b.x - p.x;
}

float box(vec2 p, vec2 lo, vec2 hi) {
  vec2 q = abs(p - (lo + hi) * 0.5) - (hi - lo) * 0.5;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float roundBox(vec2 p, vec2 lo, vec2 hi, float r) {
  vec2 q = abs(p - (lo + hi) * 0.5) - (hi - lo) * 0.5 + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// A box whose top right corner alone is rounded.
float topRightBox(vec2 p, vec2 lo, vec2 hi, float r) {
  vec2 d = p - (lo + hi) * 0.5;
  float k = (d.x > 0.0 && d.y < 0.0) ? r : 0.0;
  vec2 q = abs(d) - (hi - lo) * 0.5 + k;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - k;
}

// The convex hull of a circle of radius ra about a and one of radius rb
// about b, where the second is not inside the first.
float taper(vec2 p, vec2 a, vec2 b, float ra, float rb) {
  vec2 pb = b - a;
  float h = dot(pb, pb);
  vec2 q = vec2(abs(dot(p - a, vec2(pb.y, -pb.x))), dot(p - a, pb)) / h;
  float d = ra - rb;
  vec2 c = vec2(sqrt(h - d * d), d);
  float k = c.x * q.y - c.y * q.x;
  if (k < 0.0) return sqrt(h * dot(q, q)) - ra;
  if (k > c.x) return sqrt(h * (dot(q, q) + 1.0 - 2.0 * q.y)) - rb;
  return dot(c, q) - ra;
}

float smin(float a, float b, float k) {
  if (k <= 0.0) return min(a, b);
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// The first pane's dog ear: a box whose top left corner is a quarter circle.
float flap(vec2 p) {
  const vec2 c = vec2(85.49, 76.91);
  float d = min(
    min(topLeftArc(p, c, 16.41), segment(p, vec2(85.49, 60.5), vec2(98.23, 60.5))),
    min(segment(p, vec2(98.23, 60.5), vec2(98.23, 94.0)), segment(p, vec2(98.23, 94.0), vec2(69.08, 94.0)))
  );
  d = min(d, segment(p, vec2(69.08, 94.0), vec2(69.08, 76.91)));
  bool inside = p.x > 69.08 && p.x < 98.23 && p.y > 60.5 && p.y < 94.0 &&
      (p.x >= c.x || p.y >= c.y || length(p - c) < 16.41);
  return inside ? -d : d;
}

// A smooth union whose blending is only felt within about six units of at,
// for filling one inside corner and nothing else.
float fillet(float a, float b, float k, vec2 p, vec2 at) {
  vec2 off = p - at;
  return smin(a, b, k * exp(-dot(off, off) / 36.0));
}

// The first pane below its dog ear, with the bevel at the foot of its left
// side. The box and the foot are true distances each, so the pane's corners
// soften like every other, and the inside corner where the bevel meets the
// box softens with them.
float body0(vec2 p, float soft) {
  const vec2 a = vec2(67.06, 98.36);
  const vec2 c = vec2(67.06, 93.69);
  const vec2 b = vec2(69.08, 89.65);
  float pane = box(p, vec2(69.08, 75.64), vec2(117.41, 125.99));
  float d = min(
    min(segment(p, vec2(67.06, 125.99), a), bevel(p, a, c, b)),
    min(segment(p, b, vec2(69.08, 125.99)), segment(p, vec2(69.08, 125.99), vec2(67.06, 125.99)))
  );
  float foot = (p.y < 125.99 && p.x < 69.08 && leftOf(p, a, c, b) < 0.0) ? -d : d;
  return fillet(pane, foot, soft, p, b);
}

// Where the dog ear melts down to: the middle of its foot, on the pane.
const vec2 kFlapFoot = vec2(83.655, 86.0);

// A point seen from inside a dog ear that has shrunk to s about its foot.
vec2 melted(vec2 p, float s) {
  return kFlapFoot + (p - kFlapFoot) / s;
}

float outline0(vec2 p, float melt, float k, float soft) {
  return smin(flap(melted(p, melt)) * melt, body0(p, soft), k);
}

float flapHole(vec2 p) {
  const vec2 c = vec2(85.49, 76.91);
  float d = min(
    min(topLeftArc(p, c, 8.83), segment(p, vec2(85.49, 68.07), vec2(90.66, 68.07))),
    min(segment(p, vec2(90.66, 68.07), vec2(90.66, 82.21)), segment(p, vec2(90.66, 82.21), vec2(76.65, 82.21)))
  );
  d = min(d, segment(p, vec2(76.65, 82.21), vec2(76.65, 76.91)));
  bool inside = p.x > 76.65 && p.x < 90.66 && p.y > 68.07 && p.y < 82.21 &&
      (p.x >= c.x || p.y >= c.y || length(p - c) < 8.83);
  return inside ? -d : d;
}

// The first pane's hole, stepped down under the dog ear's own: a box beside
// the step and the body below it, whose inside corner softens with the rest.
float paneHole0(vec2 p, float soft) {
  const vec2 a = vec2(74.63, 98.36);
  const vec2 c = vec2(74.63, 93.69);
  const vec2 b = vec2(76.65, 89.78);
  const vec2 step = vec2(90.66, 89.78);
  float right = box(p, vec2(90.66, 83.21), vec2(109.84, 118.42));
  float d = min(
    min(segment(p, b, vec2(109.84, 89.78)), segment(p, vec2(109.84, 89.78), vec2(109.84, 118.42))),
    min(segment(p, vec2(109.84, 118.42), vec2(74.63, 118.42)), segment(p, vec2(74.63, 118.42), a))
  );
  d = min(d, bevel(p, a, c, b));
  float body = (p.x < 109.84 && p.y > 89.78 && p.y < 118.42 && leftOf(p, a, c, b) < 0.0) ? -d : d;
  return fillet(right, body, soft, p, step);
}

float outline1(vec2 p) { return topRightBox(p, vec2(122.59, 75.64), vec2(172.94, 125.99), 22.71); }
float hole1(vec2 p) { return topRightBox(p, vec2(130.16, 83.21), vec2(165.37, 118.42), 15.14); }
float outline2(vec2 p) { return roundBox(p, vec2(67.06, 129.15), vec2(117.41, 179.5), 5.05); }
float hole2(vec2 p) { return box(p, vec2(74.63, 136.72), vec2(109.84, 171.93)); }
float outline3(vec2 p) { return roundBox(p, vec2(122.59, 129.15), vec2(172.94, 179.5), 5.05); }
float hole3(vec2 p) { return box(p, vec2(130.16, 136.72), vec2(165.37, 171.93)); }

const vec2 kCentre0 = vec2(92.235, 100.815);
const vec2 kCentre1 = vec2(147.765, 100.815);
const vec2 kCentre2 = vec2(92.235, 154.325);
const vec2 kCentre3 = vec2(147.765, 154.325);
const vec2 kFlapCentre = vec2(83.655, 75.14);
const float kPaneHalf = 17.605;
const float kFlapHalf = 7.005;
const float kOutlineHalf = 25.175;

// Each hole's corner nearest the middle.
const vec2 kInner0 = vec2(109.84, 118.42);
const vec2 kInner1 = vec2(130.16, 118.42);
const vec2 kInner2 = vec2(109.84, 136.72);
const vec2 kInner3 = vec2(130.16, 136.72);

// Each outline's corner nearest the middle, as the circle it is rounded by,
// or would be for the two that are square.
const float kOutlineCorner = 5.05;
const vec2 kNear0 = vec2(117.41, 125.99) - kOutlineCorner;
const vec2 kNear1 = vec2(122.59 + kOutlineCorner, 125.99 - kOutlineCorner);
const vec2 kNear2 = vec2(117.41 - kOutlineCorner, 129.15 + kOutlineCorner);
const vec2 kNear3 = vec2(122.59, 129.15) + kOutlineCorner;

const float kFingertip = 0.35;

// Where p sits in a shape that has been scaled by s about c and moved by m.
vec2 into(vec2 p, vec2 c, vec2 m, float s) {
  return c + (p - m - c) / s;
}

// A shape grown by s about its centre, then rounded by r without growing.
float grown(float d, float s, float shrink, float r) {
  return d * s * shrink - r;
}

float holeShrink(float s, float extent, float r) {
  return max(0.05, 1.0 - r / (s * extent));
}

// A corner rounded by the circle of radius r about at, drawn out toward the
// middle into a finger that tapers to a fingertip. At reach 1 the tip has
// come to the middle.
float finger(vec2 p, vec2 at, float r, float reach) {
  vec2 end = at + (uMiddle - at) * reach;
  if (length(end - at) <= abs(r - kFingertip) + 1e-3) return 1e3;
  return taper(p, at, end, r, kFingertip);
}

// Where a point of a pane lands once it has been scaled by s about c and
// moved by m.
vec2 placed(vec2 x, vec2 c, vec2 m, float s) {
  return c + (x - c) * s + m;
}

float zipAt(vec2 p) {
  vec2 fromMiddle = p - uMiddle;
  return 1.0 + uNeck.w * exp(-dot(fromMiddle, fromMiddle) / 576.0);
}

// The mark's outer edge and its holes, as distances at p.
vec2 scene(vec2 p) {
  // The outlines are drawn together harder near the middle, so the gaps
  // between the panes close from there outwards.
  vec2 fromMiddle = p - uMiddle;
  float zip = zipAt(p);

  float t0 = holeShrink(uPane0.z, kOutlineHalf, uSoft.x);
  float t1 = holeShrink(uPane1.z, kOutlineHalf, uSoft.y);
  float t2 = holeShrink(uPane2.z, kOutlineHalf, uSoft.z);
  float t3 = holeShrink(uPane3.z, kOutlineHalf, uSoft.w);
  float melt = 1.0 - 0.72 * uTension.w;
  float o0 = grown(outline0(into(p, kCentre0, uPane0.xy * zip, uPane0.z * t0), melt, 6.0 * uTension.w, uSoft.x), uPane0.z, t0, uSoft.x);
  float o1 = grown(outline1(into(p, kCentre1, uPane1.xy * zip, uPane1.z * t1)), uPane1.z, t1, uSoft.y);
  float o2 = grown(outline2(into(p, kCentre2, uPane2.xy * zip, uPane2.z * t2)), uPane2.z, t2, uSoft.z);
  float o3 = grown(outline3(into(p, kCentre3, uPane3.xy * zip, uPane3.z * t3)), uPane3.z, t3, uSoft.w);
  float kOutline = uGlobal.z;
  float outlines = smin(smin(o0, o1, kOutline), smin(o2, o3, kOutline), kOutline);
  // Before that, their inner corners reach across and meet in the middle, so
  // the gap between them is closed there first and never shuts round a
  // speck. Each finger joins only its own pane until they meet.
  if (uNeck.x > 0.0) {
    float z0 = zipAt(kNear0);
    float fingers = min(
      min(finger(p, placed(kNear0, kCentre0, uPane0.xy * z0, uPane0.z * t0), kOutlineCorner * uPane0.z * t0 + uSoft.x, uNeck.x),
          finger(p, placed(kNear1, kCentre1, uPane1.xy * z0, uPane1.z * t1), kOutlineCorner * uPane1.z * t1 + uSoft.y, uNeck.x)),
      min(finger(p, placed(kNear2, kCentre2, uPane2.xy * z0, uPane2.z * t2), kOutlineCorner * uPane2.z * t2 + uSoft.z, uNeck.x),
          finger(p, placed(kNear3, kCentre3, uPane3.xy * z0, uPane3.z * t3), kOutlineCorner * uPane3.z * t3 + uSoft.w, uNeck.x))
    );
    outlines = smin(outlines, fingers, 1.5);
  }

  float s0 = holeShrink(uPane0.w, kPaneHalf, uRound.x);
  float sf = holeShrink(uPane0.w, kFlapHalf, uRound.x * kFlapHalf / kPaneHalf);
  float s1 = holeShrink(uPane1.w, kPaneHalf, uRound.y);
  float s2 = holeShrink(uPane2.w, kPaneHalf, uRound.z);
  float s3 = holeShrink(uPane3.w, kPaneHalf, uRound.w);
  vec2 inFlap = into(p, kFlapCentre, uPane0.xy, uPane0.w * sf);
  float hf = grown(flapHole(melted(inFlap, melt)) * melt, uPane0.w, sf, uRound.x * kFlapHalf / kPaneHalf);
  float h0 = grown(paneHole0(into(p, kCentre0, uPane0.xy, uPane0.w * s0), uRound.x), uPane0.w, s0, uRound.x);
  float h1 = grown(hole1(into(p, kCentre1, uPane1.xy, uPane1.w * s1)), uPane1.w, s1, uRound.y);
  float h2 = grown(hole2(into(p, kCentre2, uPane2.xy, uPane2.w * s2)), uPane2.w, s2, uRound.z);
  float h3 = grown(hole3(into(p, kCentre3, uPane3.xy, uPane3.w * s3)), uPane3.w, s3, uRound.w);
  float kHole = uGlobal.w;
  float holes = smin(smin(smin(hf, h0, kHole), smin(h1, h2, kHole), kHole), h3, kHole);

  // The holes' inner corners reach for the middle and meet there, which
  // parts the bars between them at the crossing. Each finger joins only its
  // own hole's corner, so no two meet anywhere but at the middle.
  if (uNeck.y > 0.0) {
    float fingers = min(
      min(finger(p, placed(kInner0, kCentre0, uPane0.xy, uPane0.w * s0), uRound.x, uNeck.y),
          finger(p, placed(kInner1, kCentre1, uPane1.xy, uPane1.w * s1), uRound.y, uNeck.y)),
      min(finger(p, placed(kInner2, kCentre2, uPane2.xy, uPane2.w * s2), uRound.z, uNeck.y),
          finger(p, placed(kInner3, kCentre3, uPane3.xy, uPane3.w * s3), uRound.w, uNeck.y))
    );
    holes = min(holes, fingers);
  }
  // Once they have met, the opening there widens and draws the bars' ends
  // back, rounded.
  if (uNeck.z > 0.0) {
    holes = smin(holes, length(fromMiddle) - uNeck.z, uTension.z);
  }
  // Surface tension: the holes, run together, settle into one soft window.
  if (uTension.y > 0.0) {
    float corner = min(uBlob.z, uBlob.w) * uTension.x;
    float blob = roundBox(p, uBlob.xy - uBlob.zw, uBlob.xy + uBlob.zw, corner);
    holes = mix(holes, blob, uTension.y);
  }
  return vec2(mix(outlines, holes - uRim.x, uRim.y), holes);
}

void main() {
  vec2 local = FlutterFragCoord().xy;
  float unit = uFrame.z;
  float swell = uGlobal.x;
  vec2 q = (local - uFrame.xy) / unit;
  vec2 p = uMiddle + (q - uMiddle) / swell;

  // One device pixel, in the units the distances are measured in.
  float pixel = uFrame.w / (unit * swell);
  vec2 d = scene(p);
  // Where the goo runs together or pulls apart its distances fall off more
  // slowly than true ones, and an edge measured as if they did would smear
  // over several pixels. Near an edge each is measured against how fast it
  // really changes, so every edge stays one pixel wide.
  vec2 rate = vec2(1.0);
  if (min(abs(d.x), abs(d.y)) < 3.0 * pixel) {
    vec2 across = scene(p + vec2(pixel, 0.0)) - d;
    vec2 down = scene(p + vec2(0.0, pixel)) - d;
    rate = max(sqrt(across * across + down * down) / pixel, vec2(0.05));
  }
  float ink = clamp(0.5 - d.x / (pixel * rate.x), 0.0, 1.0);
  float open = clamp(0.5 - d.y / (pixel * rate.y), 0.0, 1.0);

  vec4 frame = mix(uGround, uInk, ink);
  fragColor = frame * (1.0 - open) + uGround * ((1.0 - uGlobal.y) * open);
}
