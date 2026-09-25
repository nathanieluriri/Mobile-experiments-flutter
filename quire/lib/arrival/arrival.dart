import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'arrival_geometry.dart';
import 'arrival_handoff.dart';
import 'arrival_motion.dart';
import 'arrival_painter.dart';

/// How long a launch screen that leaves on its own takes to go once the
/// first frame is up. iOS fades its storyboard out over 0.2 s from when the
/// frame reaches the screen, which is a little after Dart has built it, and
/// the older Android starting window is gone sooner.
const kArrivalSplashFade = Duration(milliseconds: 300);

/// The longest the arrival waits for Android 12 to say its splash has gone.
/// Android says so within a few frames of the first one, and a third of a
/// second after it for a splash with nothing to hand over, so this is only
/// for a platform side that has stopped answering.
const kArrivalHandoffBackstop = Duration(milliseconds: 2000);

/// The arrival for anyone who has asked for less motion, and for a splash that
/// came up without the mark: the ground simply lifts off the screen.
const kArrivalQuietReveal = Duration(milliseconds: 240);

/// How long the goo may keep a ready arrival waiting. It loads from the app's
/// own bundle within a frame, so a load still running after this has failed.
const kArrivalShaderLimit = Duration(milliseconds: 300);

const kArrivalShader = 'shaders/arrival.frag';

/// The app's first moments: the splash's own mark, held where the platform
/// drew it until the first screen is ready under it, and then opened like a
/// window onto that screen.
class Arrival extends StatefulWidget {
  const Arrival({
    super.key,
    required this.ready,
    required this.child,
    this.handsOver = false,
    this.handoff,
  });

  /// True once the screen under the mark has something to show.
  final ValueListenable<bool> ready;

  /// Whether the platform owns its splash: it will report what it showed and
  /// say when it has taken it away. Until it reports, the first frame is
  /// bare, since the splash may have had no mark to match.
  final bool handsOver;

  final ArrivalHandoff? handoff;

  final Widget child;

  @override
  State<Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<Arrival> with SingleTickerProviderStateMixin {
  // Preserved, because a controller left to the platform's reduce motion
  // setting runs at a twentieth of its length, which would turn the quiet
  // lift-off meant for exactly those readers into a cut.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: kArrivalReveal,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final ArrivalHandoff _handoff = widget.handoff ?? ArrivalHandoff();

  ui.FragmentShader? _shader;
  bool _shaderSettled = false;
  SplashReport? _report;
  Timer? _splashLimit;
  Timer? _shaderLimit;
  bool _splashGone = false;
  bool _started = false;
  bool _quiet = false;
  bool _stillness = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _reveal.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
        // Nothing of the arrival outlives it: the arrival itself stays in the
        // tree for as long as the app does.
        _report?.dispose();
        _report = null;
        _shader?.dispose();
        _shader = null;
      }
    });
    widget.ready.addListener(_maybeStart);
    _handoff
      ..onReport = _onReport
      ..onGone = _onGone;
    _handoff.start();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _splashGone) return;
      _splashLimit = Timer(
        widget.handsOver ? kArrivalHandoffBackstop : kArrivalSplashFade,
        _onGone,
      );
    });
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(kArrivalShader);
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } on Object {
      // Without the goo the ground lifts off instead.
    }
    _shaderSettled = true;
    _maybeStart();
  }

  Future<void> _onReport(SplashReport report) async {
    if (!mounted) return;
    final old = _report;
    setState(() => _report = report);
    old?.dispose();
    await framesOnGlass();
  }

  void _onGone() {
    _splashLimit?.cancel();
    if (_splashGone) return;
    _splashGone = true;
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !mounted || !_splashGone || !widget.ready.value) return;
    if (!_shaderSettled) {
      _shaderLimit ??= Timer(kArrivalShaderLimit, () {
        _shaderSettled = true;
        _maybeStart();
      });
      return;
    }
    _shaderLimit?.cancel();
    _started = true;
    _quiet = _shader == null || _markShown == 0 || _stillness;
    if (_quiet) _reveal.duration = kArrivalQuietReveal;
    // A frame for the screen under the mark to be laid out and painted before
    // the window opens onto it.
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.endOfFrame.then((_) {
      if (mounted) _reveal.forward();
    });
  }

  @override
  void didUpdateWidget(Arrival old) {
    super.didUpdateWidget(old);
    if (old.ready != widget.ready) {
      old.ready.removeListener(_maybeStart);
      widget.ready.addListener(_maybeStart);
      _maybeStart();
    }
  }

  @override
  void dispose() {
    widget.ready.removeListener(_maybeStart);
    _splashLimit?.cancel();
    _shaderLimit?.cancel();
    _handoff.stop();
    _reveal.dispose();
    _shader?.dispose();
    _report?.dispose();
    super.dispose();
  }

  /// How much of the mark, and of the name, the splash showed: all of them
  /// unless a platform that reports says otherwise, and none of them from a
  /// platform that reports until it has.
  double get _markShown => _shown(_report?.showedMark);
  double get _nameShown =>
      _markShown == 0 ? 0 : _shown(_report?.showedName);

  double _shown(bool? reported) => widget.handsOver
      ? (reported ?? false ? 1 : 0)
      : (reported ?? true ? 1 : 0);

  ArrivalGeometry _geometry(Size size) {
    final report = _report;
    if (report == null) return ArrivalGeometry.standard(size);
    return ArrivalGeometry.measured(
      size,
      markInk: report.markInk,
      nameBox: report.nameBox,
    );
  }

  ArrivalPose _pose(ArrivalGeometry geometry, Size size) {
    if (!_started || _quiet) return ArrivalPose.rest;
    return arrivalPoseAt(
      _reveal.value * kArrivalReveal.inMilliseconds,
      geometry,
      size,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    _stillness = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _reveal,
      child: widget.child,
      builder: (context, app) {
        final geometry = _geometry(size);
        final pose = _done ? ArrivalPose.gone : _pose(geometry, size);
        final report = _report;
        Widget? overlay;
        if (!_done) {
          overlay = CustomPaint(
            size: Size.infinite,
            painter: ArrivalPainter(
              pose: pose,
              geometry: geometry,
              shader: _quiet ? null : _shader,
              pixelRatio: pixelRatio,
              showMark: _markShown,
              showName: _nameShown,
              markPixels: report?.markPixels,
              markPixelsRect: report?.markPixelsRect,
              namePixels: report?.namePixels,
            ),
          );
          if (_quiet) {
            overlay = Opacity(opacity: 1 - _reveal.value, child: overlay);
          }
          // Once the window is swelling past the screen the desk is mostly
          // what is showing, and a finger on it should reach it.
          final passing =
              _started && !_quiet && _reveal.value * kArrivalReveal.inMilliseconds >=
                  kArrivalSwellFrom;
          overlay = IgnorePointer(
            ignoring: passing,
            child: AbsorbPointer(
              child: Semantics(
                label: 'Quire',
                textDirection:
                    Directionality.maybeOf(context) ?? TextDirection.ltr,
                container: true,
                child: overlay,
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          textDirection: TextDirection.ltr,
          children: [
            Transform.scale(
              // Standing the desk forward and settling it back is motion too,
              // so a quiet arrival leaves it where it is.
              scale: _quiet ? 1 : pose.deskScale,
              child: ExcludeSemantics(excluding: !_done, child: app),
            ),
            ?overlay,
          ],
        );
      },
    );
  }
}
