import 'dart:ui';

/// How far a marker stroke leans, and how far past its letters it runs, over
/// the interface's own type.
const kMarkerLean = 1.6;
const kMarkerOverhang = 2.0;

/// The same two, as shares of the height of the letters being marked, for type
/// that is set at whatever size a document asks for rather than the app's own.
const kMarkerLeanShare = 0.085;
const kMarkerOverhangShare = 0.1;

/// A marker stroke over [box]: a touch wider than the letters, sitting off the
/// baseline, and leaning the way a hand holding a pen would lean it.
Path markerStroke(
  Rect box, {
  double lean = kMarkerLean,
  double overhang = kMarkerOverhang,
}) {
  final top = box.top + box.height * 0.14;
  final bottom = box.bottom - box.height * 0.08;
  return Path()
    ..moveTo(box.left - overhang + lean, top)
    ..lineTo(box.right + overhang + lean, top)
    ..lineTo(box.right + overhang - lean, bottom)
    ..lineTo(box.left - overhang - lean, bottom)
    ..close();
}

/// Draws the stroke over [box] with [paint], [fill] of the way across it.
///
/// A part drawn stroke is clipped from the left, so the marker looks like it is
/// still travelling across the word rather than fading in over all of it.
void paintMarkerStroke(
  Canvas canvas,
  Rect box,
  Paint paint, {
  double fill = 1,
  double lean = kMarkerLean,
  double overhang = kMarkerOverhang,
}) {
  if (fill <= 0 || box.isEmpty) return;
  final stroke = markerStroke(box, lean: lean, overhang: overhang);
  if (fill >= 1) {
    canvas.drawPath(stroke, paint);
    return;
  }
  canvas.save();
  canvas.clipRect(
    Rect.fromLTWH(
      box.left - overhang - lean,
      box.top,
      box.width * fill + (overhang + lean) * 2,
      box.height,
    ),
  );
  canvas.drawPath(stroke, paint);
  canvas.restore();
}
