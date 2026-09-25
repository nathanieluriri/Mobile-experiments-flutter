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

/// The longest the arrival waits for Android 12 to report and take its splash
/// away. It normally does so within a frame or two of the first one.
const kArrivalHandoffLimit = Duration(milliseconds: 700);

/// The arrival for anyone who has asked for less motion, and for a splash that
/// came up without the mark: the ground simply lifts off the screen.
const kArrivalQuietReveal = Duration(milliseconds: 240);

/// How long the goo may keep the arrival waiting once everything else is
/// ready. It is read off the app's own bundle and is there within a frame on
/// any phone, so a load still running after this has gone wrong, and the
/// ground lifts off instead.
const kArrivalShaderLimit = Duration(milliseconds: 300);

/// The asset the goo is drawn with.
const kArrivalShader = 'shaders/arrival.frag';

/// The app's first moments: the splash's own mark, held where the platform
/// drew it until the first screen is ready under it, and then opened like a
/// window onto that screen.
class Arrival extends StatefulWidget {
  const Arrival({
    super.key,
    required this.ready,
    required this.child,
    this.handoff,
  });

  /// True once the screen under the mark has something to show.
  final ValueListenable<bool> ready;

  final ArrivalHandoff? handoff;

  /// The app.
  final Widget child;

  @override
  State<Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<Arrival> with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: kArrivalReveal,
  );
  late final ArrivalHandoff _handoff = widget.handoff ?? ArrivalHandoff();

  ui.FragmentShader? _shader;
  bool _shaderSettled = false;
  SplashReport? _report;
  Timer? _fadeLimit;
  Timer? _handoffLimit;
  Timer? _shaderLimit;
  bool _splashGone = false;
  bool _handing = false;
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
      }
    });
    widget.ready.addListener(_maybeStart);
    _handoff
      ..onReport = _onReport
      ..onGone = _onGone;
    // Both clocks start at the first frame, whatever the platform says, and
    // an answer that never comes is the same as no.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _splashGone) return;
      _fadeLimit = Timer(kArrivalSplashFade, () {
        if (!_handing) _onGone();
      });
      _handoffLimit = Timer(kArrivalHandoffLimit, _onGone);
    });
    _handoff.start().then((handsOver) {
      if (handsOver) _handing = true;
    });
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(kArrivalShader);
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } on Object {
      // Without the goo the ground lifts off instead. A reader who never sees
      // the window open has lost a flourish, not the app.
    }
    _shaderSettled = true;
    _maybeStart();
  }

  Future<void> _onReport(SplashReport report) async {
    if (!mounted) return;
    _handing = true;
    final old = _report;
    setState(() => _report = report);
    old?.dispose();
    await framesOnGlass();
  }

  void _onGone() {
    _fadeLimit?.cancel();
    _handoffLimit?.cancel();
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
    _quiet =
        _shader == null ||
        _report?.showedMark == false ||
        _stillness;
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
    _fadeLimit?.cancel();
    _handoffLimit?.cancel();
    _shaderLimit?.cancel();
    _handoff.stop();
    _reveal.dispose();
    _shader?.dispose();
    _report?.dispose();
    super.dispose();
  }

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
        final markShown = report?.showedMark == false ? 0.0 : 1.0;
        final nameShown = report?.showedName == false ? 0.0 : markShown;
        Widget? overlay;
        if (!_done) {
          overlay = CustomPaint(
            size: Size.infinite,
            painter: ArrivalPainter(
              pose: pose,
              geometry: geometry,
              shader: _quiet ? null : _shader,
              pixelRatio: pixelRatio,
              showMark: markShown,
              showName: nameShown,
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
