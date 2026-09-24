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
uniform vec4 uBlob;    // the single window the goo settles into: centre x, y; half width, half height
uniform vec4 uTension; // that window's corner radius as a share of its half width; how much of its size it has grown to;
                       // how rounded the ends of the parting bars are; how far the dog ear has melted
uniform vec4 uGround;
uniform vec4 uInk;

out vec4 fragColor;

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

// The left side of a pane that runs straight down at x = b.x, bends along
// the quadratic from b through c to a, and runs on straight down at x = a.x.
// Negative to its right. Along the curve x only grows as y shrinks, so the
// curve's x at p's height can be solved for directly.
float leftSide(vec2 p, vec2 a, vec2 c, vec2 b) {
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
  float x = u * u * a.x + 2.0 * u * t * c.x + t * t * b.x;
  vec2 slope = 2.0 * u * (c - a) + 2.0 * t * (b - c);
  return (x - p.x) * abs(slope.y) / length(slope);
}

// A box whose top left corner is a quarter circle wider than half the box.
float topLeftArcBox(vec2 p, vec2 lo, vec2 hi, vec2 centre, float r) {
  float arc = min(
    length(p - centre) - r,
    min(box(p, vec2(centre.x, lo.y), hi), box(p, vec2(lo.x, centre.y), hi))
  );
  return max(box(p, lo, hi), arc);
}

float smin(float a, float b, float k) {
  if (k <= 0.0) return min(a, b);
  float h = max(k - abs(a - b), 0.0) / k;
  return min(a, b) - h * h * k * 0.25;
}

// Where the dog ear melts down to: the middle of its foot, on the pane.
const vec2 kFlapFoot = vec2(83.655, 86.0);

// A point seen from inside a dog ear that has shrunk to s about its foot.
vec2 melted(vec2 p, float s) {
  return kFlapFoot + (p - kFlapFoot) / s;
}

float flapOutline(vec2 p) {
  return topLeftArcBox(p, vec2(69.08, 60.5), vec2(98.23, 94.0), vec2(85.49, 76.91), 16.41);
}

float outline0(vec2 p, float melt, float k) {
  float flap = flapOutline(melted(p, melt)) * melt;
  float pane = max(
    box(p, vec2(60.0, 75.64), vec2(117.41, 125.99)),
    leftSide(p, vec2(67.06, 98.36), vec2(67.06, 93.69), vec2(69.08, 89.65))
  );
  return smin(flap, pane, k);
}

float flapHole(vec2 p) {
  return topLeftArcBox(p, vec2(76.65, 68.07), vec2(90.66, 82.21), vec2(85.49, 76.91), 8.83);
}

float paneHole0(vec2 p) {
  float right = box(p, vec2(90.66, 83.21), vec2(109.84, 118.42));
  float body = max(
    box(p, vec2(70.0, 89.78), vec2(109.84, 118.42)),
    leftSide(p, vec2(74.63, 98.36), vec2(74.63, 93.69), vec2(76.65, 89.78))
  );
  return min(right, body);
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

// Where p sits in a shape that has been scaled by s about c and moved by m.
vec2 into(vec2 p, vec2 c, vec2 m, float s) {
  return c + (p - m - c) / s;
}

// A hole grown by s about its centre, then rounded by r without growing.
float grown(float d, float s, float shrink, float r) {
  return d * s * shrink - r;
}

float holeShrink(float s, float extent, float r) {
  return max(0.05, 1.0 - r / (s * extent));
}

void main() {
  vec2 local = FlutterFragCoord().xy;
  float unit = uFrame.z;
  float swell = uGlobal.x;
  vec2 q = (local - uFrame.xy) / unit;
  vec2 p = uMiddle + (q - uMiddle) / swell;

  float t0 = holeShrink(uPane0.z, kOutlineHalf, uSoft.x);
  float t1 = holeShrink(uPane1.z, kOutlineHalf, uSoft.y);
  float t2 = holeShrink(uPane2.z, kOutlineHalf, uSoft.z);
  float t3 = holeShrink(uPane3.z, kOutlineHalf, uSoft.w);
  float melt = 1.0 - 0.72 * uTension.w;
  float o0 = grown(outline0(into(p, kCentre0, uPane0.xy, uPane0.z * t0), melt, 6.0 * uTension.w), uPane0.z, t0, uSoft.x);
  float o1 = grown(outline1(into(p, kCentre1, uPane1.xy, uPane1.z * t1)), uPane1.z, t1, uSoft.y);
  float o2 = grown(outline2(into(p, kCentre2, uPane2.xy, uPane2.z * t2)), uPane2.z, t2, uSoft.z);
  float o3 = grown(outline3(into(p, kCentre3, uPane3.xy, uPane3.z * t3)), uPane3.z, t3, uSoft.w);
  float kOutline = uGlobal.z;
  float outlines = smin(smin(o0, o1, kOutline), smin(o2, o3, kOutline), kOutline);

  float s0 = holeShrink(uPane0.w, kPaneHalf, uRound.x);
  float sf = holeShrink(uPane0.w, kFlapHalf, uRound.x * kFlapHalf / kPaneHalf);
  float s1 = holeShrink(uPane1.w, kPaneHalf, uRound.y);
  float s2 = holeShrink(uPane2.w, kPaneHalf, uRound.z);
  float s3 = holeShrink(uPane3.w, kPaneHalf, uRound.w);
  vec2 inFlap = into(p, kFlapCentre, uPane0.xy, uPane0.w * sf);
  float hf = grown(flapHole(melted(inFlap, melt)) * melt, uPane0.w, sf, uRound.x * kFlapHalf / kPaneHalf);
  float h0 = grown(paneHole0(into(p, kCentre0, uPane0.xy, uPane0.w * s0)), uPane0.w, s0, uRound.x);
  float h1 = grown(hole1(into(p, kCentre1, uPane1.xy, uPane1.w * s1)), uPane1.w, s1, uRound.y);
  float h2 = grown(hole2(into(p, kCentre2, uPane2.xy, uPane2.w * s2)), uPane2.w, s2, uRound.z);
  float h3 = grown(hole3(into(p, kCentre3, uPane3.xy, uPane3.w * s3)), uPane3.w, s3, uRound.w);
  float kHole = uGlobal.w;
  float holes = smin(smin(smin(hf, h0, kHole), smin(h1, h2, kHole), kHole), h3, kHole);
  // Surface tension: the holes, once they have run together, are pulled into
  // one soft window. Mixing the two distances rather than the two shapes is
  // what makes the bars between the holes thin, part in the middle first, and
  // draw back into the rim.
  float grow = uTension.y;
  if (grow > 0.0) {
    vec2 reach = uBlob.zw * grow;
    float corner = min(reach.x, reach.y) * mix(1.0, uTension.x, grow);
    float blob = roundBox(p, uBlob.xy - reach, uBlob.xy + reach, corner);
    float settle = smoothstep(0.55, 1.0, grow);
    holes = mix(smin(holes, blob, uTension.z), blob, settle * settle);
  }

  float outer = mix(outlines, holes - uRim.x, uRim.y);

  // One device pixel, in the units the distances above are measured in.
  float pixel = uFrame.w / (unit * swell);
  float ink = clamp(0.5 - outer / pixel, 0.0, 1.0);
  float open = clamp(0.5 - holes / pixel, 0.0, 1.0);

  vec4 frame = mix(uGround, uInk, ink);
  fragColor = frame * (1.0 - open) + uGround * ((1.0 - uGlobal.y) * open);
}
