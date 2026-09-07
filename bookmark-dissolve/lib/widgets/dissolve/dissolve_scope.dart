import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../constants/dissolve.dart';
import '../../painting/dissolve_painter.dart';
import 'dissolve_job.dart';
import 'dissolve_particles.dart';

/// Holds the runs that are in flight and hands out the two ways to start one.
class DissolveController extends ChangeNotifier {
  DissolveController(this._overlayKey);

  final GlobalKey _overlayKey;
  final List<DissolveJob> _jobs = [];
  int _nextId = 0;

  List<DissolveJob> get jobs => List.unmodifiable(_jobs);

  RenderBox? get _overlay => _overlayKey.currentContext?.findRenderObject() as RenderBox?;

  /// Snapshots the card behind [target], hides it and starts it coming apart.
  ///
  /// Returns the snapshot so the caller can keep it and put the card back
  /// later, or null when the card is not on screen.
  ui.Image? dissolve(
    GlobalKey target, {
    required double pixelRatio,
    VoidCallback? onCaptured,
    VoidCallback? onDone,
  }) {
    final box = target.currentContext?.findRenderObject();
    final overlay = _overlay;
    if (box is! RenderRepaintBoundary || overlay == null) {
      return null;
    }
    final image = box.toImageSync(pixelRatio: pixelRatio);
    onCaptured?.call();
    _add(
      DissolveJob(
        id: _nextId++,
        image: image,
        origin: box.localToGlobal(Offset.zero, ancestor: overlay),
        size: box.size,
        reverse: false,
        onDone: onDone,
      ),
    );
    return image;
  }

  /// Runs [image] backwards into the slot [target] now occupies, so the dust
  /// gathers back into a card.
  void materialize(GlobalKey target, ui.Image image, {VoidCallback? onDone}) {
    final box = target.currentContext?.findRenderObject();
    final overlay = _overlay;
    if (box is! RenderBox || overlay == null) {
      onDone?.call();
      return;
    }
    _add(
      DissolveJob(
        id: _nextId++,
        image: image,
        origin: box.localToGlobal(Offset.zero, ancestor: overlay),
        size: box.size,
        reverse: true,
        onDone: onDone,
      ),
    );
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
}

/// Wraps the app so any card below it can come apart over the whole screen.
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
          // The runs repaint every frame; the board below them must not.
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => Stack(
                    children: [
                      for (final job in _controller.jobs)
                        // The key sits on the stack's own child, so finishing one
                        // run never restarts the ones still going.
                        Positioned.fill(
                          key: ValueKey(job.id),
                          child: _DissolveRun(job: job, onDone: _controller.finish),
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

class _DissolveRunState extends State<_DissolveRun> with SingleTickerProviderStateMixin {
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
    );
    _progress = AnimationController(
      vsync: this,
      duration: job.reverse ? kMaterializeDuration : kDissolveDuration,
      reverseDuration: kMaterializeDuration,
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
      painter: DissolvePainter(image: widget.job.image, particles: _particles, progress: _progress),
    );
  }
}
