import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../theme/colors.dart';

/// The controls of present mode as one body, before the blur and the
/// threshold above it turn them into goo.
///
/// Everything here is drawn solid and in one colour. The layer above blurs the
/// lot as a single image and cuts it at an alpha, so two shapes that were
/// painted at different alphas would survive that cut as a seam through
/// something meant to be one piece.
///
/// The controls start as one blob under the slide and are pulled apart: the
/// pill stretches out of the centre, and the way out is drawn off the end of
/// it on a neck that thins and lets go. That is the whole reason the cluster
/// is goo rather than two fading buttons. A presentation has one set of
/// controls, and they should arrive as one thing.
class PresentGooPainter extends CustomPainter {
  const PresentGooPainter({
    required this.t,
    required this.pillWidth,
    required this.pillHeight,
    required this.leaveDiameter,
    required this.leaveGap,
  });

  /// 0 with the cluster gone, 1 with it fully out.
  final double t;

  /// The pill at rest, and the button that leaves.
  final double pillWidth;
  final double pillHeight;
  final double leaveDiameter;

  /// The gap between the pill's end and the button's near edge, at rest.
  final double leaveGap;

  /// Where the two travel from: the middle of the canvas, which is where the
  /// pill sits and where the whole body starts as one circle.
  Offset _origin(Size size) => Offset(size.width / 2, size.height / 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final paint = Paint()..color = AppColors.surfaceHigh;
    final origin = _origin(size);
    final eased = t.clamp(0.0, 1.0);

    // The pill grows out of the centre along its own length, so it reads as
    // one body stretching rather than a shape scaling up.
    final width = math.max(pillHeight, pillWidth * eased);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: origin,
          width: width,
          height: pillHeight,
        ),
        Radius.circular(pillHeight / 2),
      ),
      paint,
    );

    // The way out travels off the pill's right end. Its full reach is the
    // pill's half width, the gap, and its own radius.
    final reach = pillWidth / 2 + leaveGap + leaveDiameter / 2;
    final centre = Offset(origin.dx + reach * eased, origin.dy);
    _neck(canvas, paint, origin, centre, width / 2);
    canvas.drawCircle(centre, leaveDiameter / 2 * eased, paint);
  }

  /// Circles strung between the pill's end and the button, tapering to a
  /// waist, so the two read as one body being pulled apart.
  ///
  /// The run thins as the button travels and is gone by the time it arrives,
  /// which is the moment the goo lets go.
  void _neck(
    Canvas canvas,
    Paint paint,
    Offset origin,
    Offset centre,
    double pillHalf,
  ) {
    final from = Offset(origin.dx + pillHalf, origin.dy);
    final travelled = centre.dx - from.dx;
    if (travelled <= 0) return;
    final left = 1 - (travelled / (leaveGap + leaveDiameter)).clamp(0.0, 1.0);
    if (left <= 0) return;
    const circles = 3;
    for (var i = 1; i <= circles; i++) {
      final along = i / (circles + 1);
      // A waist: thinnest in the middle of the run, thicker at both ends.
      final waist = 1 - 0.38 * math.sin(along * math.pi);
      final radius =
          (pillHeight / 2) * left * waist * (1 - along) +
          (leaveDiameter / 2) * left * waist * along;
      if (radius <= 0.2) continue;
      canvas.drawCircle(
        Offset(from.dx + travelled * along, origin.dy),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PresentGooPainter old) =>
      old.t != t ||
      old.pillWidth != pillWidth ||
      old.pillHeight != pillHeight ||
      old.leaveDiameter != leaveDiameter ||
      old.leaveGap != leaveGap;
}
