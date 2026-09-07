import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../../constants/gooey_fab.dart';
import 'delayed_simulation.dart';

/// One animated value plus the spring currently carrying it, so a toggle that
/// lands mid flight can let that spring finish out a stagger.
class _Drive {
  _Drive(this.controller);

  final AnimationController controller;
  SpringDescription? spring;
  double? target;

  /// A fresh copy of the spring in flight, rebased to start now. Springs are
  /// memoryless, so this continues the motion exactly.
  Simulation? get inFlight {
    if (!controller.isAnimating || spring == null) {
      return null;
    }
    return SpringSimulation(spring!, controller.value, target!, controller.velocity);
  }
}

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
      videoDrive = AnimationController.unbounded(vsync: vsync) {
    _progress = _Drive(progress);
    _voice = _Drive(voiceDrive);
    _video = _Drive(videoDrive);
  }

  /// 0 closed, 1 open. Drives the backdrop and the plus rotation.
  final AnimationController progress;

  /// 0 parked on the FAB, 1 at its open offset.
  final AnimationController voiceDrive;
  final AnimationController videoDrive;

  late final _Drive _progress;
  late final _Drive _voice;
  late final _Drive _video;

  bool get isOpen => _isOpen;
  bool _isOpen = false;

  /// Everything that changes when any of the three values move.
  Listenable get animations => Listenable.merge([progress, voiceDrive, videoDrive]);

  void toggle() {
    if (_isOpen) {
      _springTo(_progress, 0, closeSpring);
      _springTo(_video, 0, closeSpring);
      _springTo(_voice, 0, closeSpring, delay: actionStagger);
    } else {
      _springTo(_progress, 1, openSpring);
      _springTo(_voice, 1, openSpring);
      _springTo(_video, 1, videoOpenSpring, delay: actionStagger);
    }
    _isOpen = !_isOpen;
    notifyListeners();
  }

  void _springTo(_Drive drive, double target, SpringDescription spring, {Duration? delay}) {
    final controller = drive.controller;
    final from = controller.value;
    final velocity = controller.velocity;
    final carry = delay == null ? null : drive.inFlight;
    drive.spring = spring;
    drive.target = target;

    if (delay == null) {
      controller.animateWith(SpringSimulation(spring, from, target, velocity));
      return;
    }
    controller.animateWith(
      DelayedSimulation(
        delay: delay.inMicroseconds / Duration.microsecondsPerSecond,
        hold: from,
        carry: carry,
        build: (value, velocity) => SpringSimulation(spring, value, target, velocity),
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
