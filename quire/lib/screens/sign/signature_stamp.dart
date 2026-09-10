import 'package:flutter/widgets.dart';

import '../../painting/signature_painter.dart';
import '../../theme/colors.dart';

/// The scale handle's side, at the stamp's bottom right corner.
const kStampHandle = 34.0;

/// The knob drawn inside that target.
const kStampKnob = 15.0;

/// The dashed outline around a mark that has not landed yet: 3 on, 3 off.
const kStampDashOn = 3.0;
const kStampDashOff = 3.0;

/// The two arms of the handle's corner bracket.
const kStampHandleArm = 12.0;

/// A signature that has been picked up but not yet set into the page.
///
/// It draws two separate things over each other on purpose: the mark, and the
/// dashed outline that says it is still loose. Only the mark sits inside
/// [inkKey], because the outline is chrome, and chrome must not end up in the
/// snapshot the grains of the absorb are made of.
class SignatureStamp extends StatelessWidget {
  const SignatureStamp({
    super.key,
    required this.mark,
    required this.inkKey,
    this.ink = 1,
    this.outline = 1,
    this.onDrag,
    this.onScale,
    this.onPinchStart,
    this.onPinch,
  });

  final SignatureMark mark;

  /// The boundary the absorb snapshots. It holds the mark and nothing else.
  final Key inkKey;

  /// How opaque the mark itself is. It drops to 0 the instant the grains take
  /// over, so the reader never sees the mark twice.
  final double ink;

  /// How far in the dashed outline still is, 1 to 0 across [kStampOutlineFade].
  final double outline;

  /// Moves the whole stamp.
  final ValueChanged<Offset>? onDrag;

  /// Grows and shrinks it from the corner.
  final ValueChanged<Offset>? onScale;

  /// A second finger has landed, so whatever comes next is measured from the
  /// size the mark is now.
  final VoidCallback? onPinchStart;

  /// Two fingers, spread or pinched, as a factor of the size at the start of
  /// the gesture.
  final ValueChanged<double>? onPinch;

  @override
  Widget build(BuildContext context) {
    // One recogniser for both, because a drag and a pinch are the same
    // gesture with a different number of fingers, and two recognisers would
    // spend the whole placement arguing about which of them had the touch.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => onPinchStart?.call(),
      onScaleUpdate: (details) {
        onDrag?.call(details.focalPointDelta);
        if (details.pointerCount > 1) onPinch?.call(details.scale);
      },
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              key: inkKey,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _StampInkPainter(mark: mark, opacity: ink),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _StampOutlinePainter(outline)),
            ),
          ),
          if (outline > 0)
            Positioned(
              right: 0,
              bottom: 0,
              width: kStampHandle,
              height: kStampHandle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => onScale?.call(details.delta),
                child: Opacity(
                  opacity: outline,
                  child: const CustomPaint(painter: _StampHandlePainter()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The mark itself, at the alpha a signature keeps once it is dry.
class _StampInkPainter extends CustomPainter {
  const _StampInkPainter({required this.mark, required this.opacity});

  final SignatureMark mark;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (mark.isEmpty || opacity <= 0) return;
    mark.paintInto(
      canvas,
      Offset.zero & size,
      alpha: kPlacedInkAlpha * opacity,
    );
  }

  @override
  bool shouldRepaint(_StampInkPainter old) =>
      old.opacity != opacity || old.mark != mark;
}

/// The dashed box that says the mark has not landed yet.
class _StampOutlinePainter extends CustomPainter {
  const _StampOutlinePainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.accent.withValues(alpha: opacity);
    final box = Offset.zero & size;
    _dash(canvas, box.topLeft, box.topRight, paint);
    _dash(canvas, box.topRight, box.bottomRight, paint);
    _dash(canvas, box.bottomRight, box.bottomLeft, paint);
    _dash(canvas, box.bottomLeft, box.topLeft, paint);
  }

  void _dash(Canvas canvas, Offset from, Offset to, Paint paint) {
    final total = (to - from).distance;
    if (total <= 0) return;
    final step = (to - from) / total;
    var at = 0.0;
    while (at < total) {
      final end = (at + kStampDashOn).clamp(0.0, total);
      canvas.drawLine(from + step * at, from + step * end, paint);
      at = end + kStampDashOff;
    }
  }

  @override
  bool shouldRepaint(_StampOutlinePainter old) => old.opacity != opacity;
}

/// The corner you take hold of to make the mark bigger or smaller.
/// The knob that resizes the mark: a filled corner with the two arms of the
/// bracket cut out of it.
///
/// It was a pair of hairlines, which is a mark on a page and not a thing to
/// take hold of. A reader who cannot see a handle drags the whole signature
/// around instead and concludes it cannot be resized at all.
class _StampHandlePainter extends CustomPainter {
  const _StampHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final corner = Offset(size.width, size.height);
    final centre = corner - const Offset(kStampKnob / 2, kStampKnob / 2);
    canvas.drawCircle(
      centre,
      kStampKnob / 2,
      Paint()..color = AppColors.accent,
    );
    final arms = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = AppColors.onAccent;
    // A corner bracket inside the knob, pointing the way it grows.
    const reach = kStampHandleArm / 3;
    final elbow = centre + const Offset(reach, reach);
    canvas.drawLine(elbow - const Offset(reach * 2, 0), elbow, arms);
    canvas.drawLine(elbow - const Offset(0, reach * 2), elbow, arms);
  }

  @override
  bool shouldRepaint(_StampHandlePainter old) => false;
}
