import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../constants/dissolve.dart';
import '../../painting/dissolve_painter.dart';
import '../../theme/metrics.dart';
import 'dissolve_job.dart';
import 'dissolve_particles.dart';

/// Holds the runs that are in flight and hands out the ways to start one.
class DissolveController extends ChangeNotifier {
  DissolveController(this._overlayKey);

  final GlobalKey _overlayKey;
  final List<DissolveJob> _jobs = [];
  int _nextId = 0;

  List<DissolveJob> get jobs => List.unmodifiable(_jobs);

  RenderBox? get _overlay =>
      _overlayKey.currentContext?.findRenderObject() as RenderBox?;

  /// Snapshots the sheet behind [target], hides it and starts it coming apart.
  ///
  /// Returns the snapshot so the caller can keep it and put the sheet back
  /// later, or null when the sheet is not on screen.
  ui.Image? dissolve(
    GlobalKey target, {
    required double pixelRatio,
    Duration duration = kDissolve,
    ParticleMotionSet motion = ParticleMotionSet.dust,
    VoidCallback? onCaptured,
    VoidCallback? onDone,
  }) {
    final image = _snapshot(target, pixelRatio);
    if (image == null) {
      return null;
    }
    onCaptured?.call();
    _add(
      DissolveJob(
        id: _nextId++,
        image: image,
        origin: _originOf(target)!,
        size: (target.currentContext!.findRenderObject()! as RenderBox).size,
        reverse: false,
        duration: duration,
        motion: motion,
        onDone: onDone,
      ),
    );
    return image;
  }

  /// Runs [image] backwards into the slot [target] now occupies, so the dust
  /// gathers back into a sheet.
  void materialize(
    GlobalKey target,
    ui.Image image, {
    Duration duration = kMaterialize,
    ParticleMotionSet motion = ParticleMotionSet.dust,
    VoidCallback? onDone,
  }) {
    final box = target.currentContext?.findRenderObject();
    final origin = _originOf(target);
    if (box is! RenderBox || origin == null) {
      onDone?.call();
      return;
    }
    _add(
      DissolveJob(
        id: _nextId++,
        image: image,
        origin: origin,
        size: box.size,
        reverse: true,
        duration: duration,
        motion: motion,
        onDone: onDone,
      ),
    );
  }

  /// Snapshots [target] and sinks it into whatever is under it: the same
  /// painter and the same atlas, with the grains too heavy to blow anywhere.
  ui.Image? absorb(
    GlobalKey target, {
    required double pixelRatio,
    VoidCallback? onCaptured,
    VoidCallback? onDone,
  }) {
    final image = _snapshot(target, pixelRatio);
    if (image == null) {
      return null;
    }
    onCaptured?.call();
    materialize(
      target,
      image,
      duration: kAbsorb,
      motion: ParticleMotionSet.absorb,
      onDone: onDone,
    );
    return image;
  }

  ui.Image? _snapshot(GlobalKey target, double pixelRatio) {
    final box = target.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || _overlay == null) {
      return null;
    }
    return box.toImageSync(pixelRatio: pixelRatio);
  }

  ui.Offset? _originOf(GlobalKey target) {
    final box = target.currentContext?.findRenderObject();
    final overlay = _overlay;
    if (box is! RenderBox || overlay == null) {
      return null;
    }
    return box.localToGlobal(Offset.zero, ancestor: overlay);
  }

  void _add(DissolveJob job) {
    _jobs.add(job);
    notifyListeners();
  }

  void finish(DissolveJob job) {
    job.onDone?.call();
    _jobs.remove(job);
    notifyListeners();
  }

  /// Drops every run in flight and puts the job counter back to zero.
  ///
  /// A test resets rather than shares, so job ids start from a known value and
  /// a keyframe part way through a run is the same picture every time.
  void reset() {
    _jobs.clear();
    _nextId = 0;
    notifyListeners();
  }
}

/// Wraps the app so any sheet below it can come apart over the whole screen.
class DissolveScope extends StatefulWidget {
  const DissolveScope({super.key, required this.child});

  final Widget child;

  static DissolveController of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_DissolveScope>();
    assert(scope != null, 'No DissolveScope above this widget.');
    return scope!.controller;
  }

  @override
  State<DissolveScope> createState() => _DissolveScopeState();
}

class _DissolveScopeState extends State<DissolveScope> {
  final _overlayKey = GlobalKey();
  late final DissolveController _controller = DissolveController(_overlayKey);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DissolveScope(
      controller: _controller,
      child: Stack(
        key: _overlayKey,
        children: [
          widget.child,
          // The runs repaint every frame; the screen below them must not.
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Stack(
                    children: [
                      for (final job in _controller.jobs)
                        // The key sits on the stack's own child, so finishing
                        // one run never restarts the ones still going.
                        Positioned.fill(
                          key: ValueKey(job.id),
                          child: _DissolveRun(
                            job: job,
                            onDone: _controller.finish,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DissolveScope extends InheritedWidget {
  const _DissolveScope({required this.controller, required super.child});

  final DissolveController controller;

  @override
  bool updateShouldNotify(_DissolveScope old) => old.controller != controller;
}

/// One job, running its progress from 0 to 1 or back again.
class _DissolveRun extends StatefulWidget {
  const _DissolveRun({required this.job, required this.onDone});

  final DissolveJob job;
  final void Function(DissolveJob) onDone;

  @override
  State<_DissolveRun> createState() => _DissolveRunState();
}

class _DissolveRunState extends State<_DissolveRun>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  late final DissolveParticles _particles;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    _particles = DissolveParticles(
      image: job.image,
      origin: job.origin,
      size: job.size,
      seed: job.id,
      motion: job.motion,
    );
    _progress = AnimationController(
      vsync: this,
      duration: job.duration,
      reverseDuration: job.duration,
      value: job.reverse ? 1 : 0,
    );
    final run = job.reverse ? _progress.reverse() : _progress.forward();
    run.then((_) {
      if (mounted) {
        widget.onDone(job);
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DissolvePainter(
        image: widget.job.image,
        particles: _particles,
        progress: _progress,
      ),
    );
  }
}
