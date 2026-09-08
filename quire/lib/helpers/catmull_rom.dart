import 'dart:ui';

/// The tension a signature stroke is smoothed at. 0.5 is the centripetal
/// value: it passes through every sample and never loops back on itself, which
/// a looser spline does on a fast flourish.
const kStrokeTension = 0.5;

/// How far apart the resampled points sit along the smoothed centre line.
const kResampleStep = 2.0;

/// One point of [samples] evaluated on the Catmull-Rom spline through them.
///
/// [segment] indexes the sample the piece starts at and [t] runs 0 to 1 across
/// that piece. The ends are handled by duplicating the first and last sample,
/// so a stroke starts and finishes exactly where the finger did.
Offset catmullRomPoint(
  List<Offset> samples,
  int segment,
  double t, {
  double tension = kStrokeTension,
}) {
  Offset at(int i) => samples[i.clamp(0, samples.length - 1)];
  final p0 = at(segment - 1);
  final p1 = at(segment);
  final p2 = at(segment + 1);
  final p3 = at(segment + 2);

  final t2 = t * t;
  final t3 = t2 * t;
  final m1 = (p2 - p0) * tension;
  final m2 = (p3 - p1) * tension;

  final a = p1 * (2 * t3 - 3 * t2 + 1);
  final b = m1 * (t3 - 2 * t2 + t);
  final c = p2 * (-2 * t3 + 3 * t2);
  final d = m2 * (t3 - t2);
  return a + b + c + d;
}

/// Resamples [samples] along the Catmull-Rom spline through them, one point
/// every [step] logical pixels of arc length.
///
/// A raw touch stream is uneven: the same gesture gives long jumps where the
/// hand moved fast and a cluster where it paused. Ribbon geometry needs even
/// spacing, because the width at each point comes from the speed between
/// points, and a cluster would read as a blob.
List<Offset> resampleStroke(
  List<Offset> samples, {
  double step = kResampleStep,
  double tension = kStrokeTension,
}) {
  if (samples.length < 2) {
    return List<Offset>.of(samples);
  }
  final out = <Offset>[samples.first];
  var carried = 0.0;
  for (var segment = 0; segment < samples.length - 1; segment++) {
    final length = (samples[segment + 1] - samples[segment]).distance;
    // Enough subdivisions that a curved piece is walked in short hops, with a
    // floor so a very short piece is still sampled at both ends.
    final divisions = (length / (step / 2)).ceil().clamp(2, 512);
    var previous = catmullRomPoint(samples, segment, 0, tension: tension);
    for (var i = 1; i <= divisions; i++) {
      final point = catmullRomPoint(
        samples,
        segment,
        i / divisions,
        tension: tension,
      );
      final total = (point - previous).distance;
      if (total == 0) {
        continue;
      }
      var walked = 0.0;
      while (carried + (total - walked) >= step) {
        walked += step - carried;
        carried = 0;
        out.add(Offset.lerp(previous, point, walked / total)!);
      }
      carried += total - walked;
      previous = point;
    }
  }
  if ((out.last - samples.last).distance > 1e-6) {
    out.add(samples.last);
  }
  return out;
}
