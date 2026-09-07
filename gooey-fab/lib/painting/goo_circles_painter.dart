import 'package:flutter/rendering.dart';

import '../constants/gooey_fab.dart';
import '../theme/colors.dart';

/// The three solid circles the goo layer blurs and thresholds: the two action
/// circles at their current heights, and the FAB itself.
class GooCirclesPainter extends CustomPainter {
  const GooCirclesPainter({required this.voiceCenterY, required this.videoCenterY});

  final double voiceCenterY;
  final double videoCenterY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.ink;
    canvas.drawCircle(Offset(fabCenterX, videoCenterY), actionDiameter / 2, paint);
    canvas.drawCircle(Offset(fabCenterX, voiceCenterY), actionDiameter / 2, paint);
    canvas.drawCircle(const Offset(fabCenterX, fabCenterY), fabDiameter / 2, paint);
  }

  @override
  bool shouldRepaint(GooCirclesPainter oldDelegate) =>
      oldDelegate.voiceCenterY != voiceCenterY || oldDelegate.videoCenterY != videoCenterY;
}
