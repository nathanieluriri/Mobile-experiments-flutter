import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';
import 'delayed_simulation.dart';

/// Drives the three values the FAB animates: the open progress the backdrop and
/// the plus icon follow, and one drive per action circle.
///
/// Opening runs the voice circle first and the video circle one stagger later
/// on a looser spring, so it overshoots further. Closing reverses the order and
/// uses a stiffer spring.
class GooeyFabController extends ChangeNotifier {
  GooeyFabController({required TickerProvider vsync})
    : progress = AnimationController.unbounded(vsync: vsync),
      voiceDrive = AnimationController.unbounded(vsync: vsync),
      videoDrive = AnimationController.unbounded(vsync: vsync);

  /// 0 closed, 1 open. Drives the backdrop and the plus rotation.
  final AnimationController progress;

  /// 0 parked on the FAB, 1 at its open offset.
  final AnimationController voiceDrive;
  final AnimationController videoDrive;

  bool get isOpen => _isOpen;
  bool _isOpen = false;

  /// Everything that changes when any of the three values move.
  Listenable get animations => Listenable.merge([progress, voiceDrive, videoDrive]);

  void toggle() {
    if (_isOpen) {
      _springTo(progress, 0, closeSpring);
      _springTo(videoDrive, 0, closeSpring);
      _springTo(voiceDrive, 0, closeSpring, delay: actionStagger);
    } else {
      _springTo(progress, 1, openSpring);
      _springTo(voiceDrive, 1, openSpring);
      _springTo(videoDrive, 1, videoOpenSpring, delay: actionStagger);
    }
    _isOpen = !_isOpen;
    notifyListeners();
  }

  void _springTo(
    AnimationController controller,
    double target,
    SpringDescription spring, {
    Duration? delay,
  }) {
    final from = controller.value;
    if (delay == null) {
      controller.animateWith(SpringSimulation(spring, from, target, controller.velocity));
      return;
    }
    controller.animateWith(
      DelayedSimulation(
        inner: SpringSimulation(spring, from, target, 0),
        delay: delay.inMicroseconds / Duration.microsecondsPerSecond,
        startValue: from,
      ),
    );
  }

  @override
  void dispose() {
    progress.dispose();
    voiceDrive.dispose();
    videoDrive.dispose();
    super.dispose();
  }
}
