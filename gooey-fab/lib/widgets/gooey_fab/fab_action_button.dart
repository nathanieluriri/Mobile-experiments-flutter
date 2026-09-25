import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';

/// One action circle. It rides its drive value from the FAB out to [offsetY],
/// scaling up and fading in over the last part of the trip.
///
/// The travel is a change of position rather than a paint transform so the
/// circle can be tapped where it is drawn.
class FabActionButton extends StatelessWidget {
  const FabActionButton({
    super.key,
    required this.drive,
    required this.offsetY,
    required this.interactive,
    required this.onPressed,
    required this.child,
  });

  final Animation<double> drive;
  final double offsetY;
  final bool interactive;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: drive,
      builder: (context, child) {
        final value = drive.value;
        return Positioned(
          left: fabCenterX - actionDiameter / 2,
          top: fabCenterY - actionDiameter / 2 + value * offsetY,
          width: actionDiameter,
          height: actionDiameter,
          child: IgnorePointer(
            ignoring: !interactive,
            child: Transform.scale(
              scale: interpolateClamped(
                value,
                actionScaleInputRange,
                actionScaleOutputRange,
              ),
              child: Opacity(
                opacity: interpolateClamped(
                  value,
                  actionOpacityInputRange,
                  actionOpacityOutputRange,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Center(child: child),
      ),
    );
  }
}
