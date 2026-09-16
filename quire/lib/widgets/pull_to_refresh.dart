import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../config/flags.dart';
import '../painting/spinner_painter.dart';
import '../theme/colors.dart';
import '../theme/easings.dart';
import '../theme/feedback.dart';

/// How far the list has to be pulled before letting go means anything.
const kPullThreshold = 76.0;

/// How far it may be pulled at all. Past this the list stops following, so
/// there is an end to the gesture rather than an arm's length of nothing.
const kPullLimit = 128.0;

/// Where the loop rests while it is working, measured from the top of the body.
const kPullRest = 60.0;

/// How long the loop takes to leave once the work is done, and how long it
/// holds at rest before it does.
const kPullRetract = Duration(milliseconds: 260);
const kPullHold = Duration(milliseconds: 180);

/// How far the loop turns over the whole pull, before it is doing anything.
///
/// Most of one turn: enough that the wave is visibly travelling under the
/// finger, and short of a full revolution so the loop does not appear to have
/// completed something it has not started.
const double kPullTurns = 0.75;

/// How far the goo swells past the loop it is carrying.
const double kNeckHug = 5.0;

/// How far the goo's edge breathes in and out, as a share of its radius.
const double kGooWobble = 0.055;

/// How many lobes that breathing has. Three reads as a body settling rather
/// than as a cog turning.
const int kGooLobes = 3;

/// How much of the list the goo takes the light off while it works, so what
/// it is over reads as being under it.
///
/// The app draws no shadows, so depth is a difference in value: the list goes
/// quiet, the goo does not, and the eye puts the goo in front.
const double kPullHush = 0.66;

/// A list you pull down to read again.
///
/// The loop is the app's own, and it is driven by the finger rather than by a
/// clock until the finger lets go. That is the whole point of the gesture:
/// what is on screen is a readout of how far you have pulled, so the moment it
/// will fire is a thing you can see arriving rather than a distance you have
/// to guess at. It only starts turning on its own once it has been handed
/// something to do.
///
/// It works off overscroll rather than off a negative scroll offset, because
/// on Android a list at its top does not go negative: it reports the pull and
/// stays where it is. Reading the offset would mean this gesture existed on
/// one platform.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.enabled = true,
    this.style = kPullStyle,
  });

  /// Which of the three answers to a pull this one gives.
  final PullStyle style;

  final Widget child;

  /// The work. The loop turns until this is done, however long that is.
  final Future<void> Function() onRefresh;

  /// False where a pull would mean nothing, such as a destination that is not
  /// a list of documents.
  final bool enabled;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh>
    with TickerProviderStateMixin {
  /// How far the finger has pulled past the top, in points.
  double _pull = 0;

  /// True from the moment the work starts until the loop has gone again.
  bool _working = false;

  /// True once this pull has passed the mark, so the bump is felt once.
  bool _armed = false;

  /// The loop's own turn while it is working, and its retraction after.
  ///
  /// Made when the widget is, not on first use. Most lists are never pulled,
  /// and a controller that is only built when it is first read is a controller
  /// built by its own dispose, which reaches for the ticker of a widget that
  /// has already left the tree.
  late final AnimationController _turn;
  late final AnimationController _leave;

  /// The crinkle travelling round the ring, once, as the work starts.
  late final AnimationController _trace;

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: kSpinnerPeriod);
    _leave = AnimationController(vsync: this, duration: kPullRetract);
    _trace = AnimationController(vsync: this, duration: kSpinnerTrace);
  }

  @override
  void dispose() {
    _turn.dispose();
    _leave.dispose();
    _trace.dispose();
    super.dispose();
  }

  /// How far down the loop is drawn, and how much of it there is.
  double get _shown =>
      _working ? kPullRest * (1 - easeOutCubic.transform(_leave.value)) : _pull;

  bool _onScroll(ScrollNotification notification) {
    if (!widget.enabled || _working) return false;
    // Only the list this wraps, not a row's own sideways scroller.
    if (notification.depth != 0) return false;

    if (notification is OverscrollNotification) {
      final over = notification.overscroll;
      // Negative is a pull downward at the top. A fling that runs off the
      // bottom is somebody else's overscroll and is not this gesture.
      if (over >= 0 || notification.metrics.pixels > 0) return false;
      _setPull((_pull - over).clamp(0.0, kPullLimit));
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      // Physics that let the list run past its own top (which is what iOS
      // does) never overscroll: the pull is in the offset itself.
      final past = -notification.metrics.pixels;
      if (past > 0) {
        _setPull(past.clamp(0.0, kPullLimit));
        // Such a list springs back on its own, and by the time it has settled
        // the pull is already gone, so the decision is made at the moment the
        // finger leaves rather than at the end of the scroll.
        if (notification.dragDetails == null && _pull >= kPullThreshold) {
          unawaited(_run());
        }
        return false;
      }
      if (_pull > 0) {
        final delta = notification.scrollDelta ?? 0;
        if (delta > 0) _setPull((_pull - delta).clamp(0.0, kPullLimit));
      }
      return false;
    }
    if (notification is ScrollEndNotification && _pull > 0) {
      if (_pull >= kPullThreshold) {
        unawaited(_run());
      } else {
        _setPull(0);
      }
      return false;
    }
    return false;
  }

  void _setPull(double next) {
    if (next == _pull) return;
    setState(() => _pull = next);
    // The mark is a thing you feel arriving, once, on the way out and not
    // again on the way back.
    final past = _pull >= kPullThreshold;
    if (past && !_armed) {
      _armed = true;
      Feel.turn.ring();
    } else if (!past) {
      _armed = false;
    }
  }

  Future<void> _run() async {
    setState(() {
      _working = true;
      _pull = kPullRest;
    });
    _leave.value = 0;
    // A plain circle until there is work. The zig zag is what working looks
    // like, so it is drawn on at the moment the work starts.
    _trace.forward(from: 0);
    _turn.repeat();
    Feel.commit.ring();
    try {
      await widget.onRefresh();
    } finally {
      await _settle();
    }
  }

  /// Holds the loop a moment so the work is seen to have happened, takes it
  /// back up, and puts the pull away.
  ///
  /// Every step checks that this state is still here first. The list can be
  /// put away at any point in the hold or the retract, and often is: what the
  /// work changes is the list itself, and a desk left with nothing on it
  /// replaces the body this lives in.
  Future<void> _settle() async {
    if (!mounted) return;
    await Future<void>.delayed(kPullHold);
    if (!mounted) return;
    await _leave.forward();
    if (!mounted) return;
    _turn.stop();
    _trace.value = 0;
    setState(() {
      _working = false;
      _pull = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_turn, _leave, _trace]),
        builder: (context, _) {
          final down = _shown;
          final reach = (_pull / kPullThreshold).clamp(0.0, 1.0);
          final goo = widget.style == PullStyle.goo;
          final loop = _Loop(
            down: down,
            // Before it is working the loop is a readout of the pull, and
            // after it is a loop.
            turns: _working ? _turn.value : reach * kPullTurns,
            reach: reach,
            working: _working,
            // The goo does the talking in its own style, so the ring inside
            // it stays a plain circle rather than crinkling as well.
            trace: _working && !goo ? _trace.value : 0,
            // 1 while it is still part of the top edge, 0 once it has been
            // pulled clear, and back to 1 as it is taken up again: the goo
            // comes out of the edge, works loose of it, and melts back into
            // it, rather than appearing and vanishing.
            attach: _working ? _leave.value : 1 - reach,
            style: widget.style,
          );
          // The hush comes up with the work and goes with the retract.
          final hush = goo && _working
              ? kPullHush * _trace.value * (1 - _leave.value)
              : 0.0;
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: switch (widget.style) {
                  // The list opens a space at its head and the loop sits in
                  // it, so what is being pulled is the list itself.
                  PullStyle.follow => Transform.translate(
                    offset: Offset(0, down),
                    child: widget.child,
                  ),
                  // The list holds still. Only the loop moves, over the top
                  // of it.
                  PullStyle.overlay || PullStyle.goo => widget.child,
                },
              ),
              if (hush > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: AppColors.ground.withValues(alpha: hush),
                    ),
                  ),
                ),
              if (_pull > 0 || _working)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(child: loop),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The loop itself, at whatever point of the pull it has reached.
class _Loop extends StatelessWidget {
  const _Loop({
    required this.down,
    required this.turns,
    required this.reach,
    required this.working,
    required this.trace,
    required this.attach,
    required this.style,
  });

  /// How far the crinkle has travelled round the ring.
  final double trace;

  /// How much of the goo is still part of the top edge: 1 joined, 0 clear.
  final double attach;

  /// Which answer to a pull this is drawing.
  final PullStyle style;

  /// How far below the top of the body the loop's centre sits.
  final double down;

  final double turns;

  /// 0 at the top of the list, 1 at the mark where letting go means refresh.
  final double reach;

  final bool working;

  @override
  Widget build(BuildContext context) {
    // It grows into being rather than appearing: at the first few points of
    // the pull it is a suggestion, and it is whole by the time it would fire.
    final size = kSpinnerSize * (0.55 + 0.45 * reach);
    // In the goo style the ring is inside the goo the whole way through.
    final held = style == PullStyle.goo;
    final colour = held
        // Inside the goo, so it is drawn in the colour that sits on the
        // accent rather than in one that would disappear into it.
        ? AppColors.onAccent
        : working || reach >= 1
        ? AppColors.accentBright
        : AppColors.inkFaint;
    // In the follow style the list has opened a space and the loop belongs
    // in the middle of it, clear of the first row. In the other two the list
    // has not moved, so the loop comes down over it.
    final centre = switch (style) {
      PullStyle.follow => ((down - kSpinnerSize) / 2).clamp(0.0, kPullLimit),
      PullStyle.overlay ||
      PullStyle.goo => (down - kSpinnerSize / 2).clamp(0.0, kPullLimit),
    };
    return SizedBox(
      height: (centre + kSpinnerSize).clamp(0.0, kPullLimit + kSpinnerSize),
      child: Stack(
        children: <Widget>[
          // The goo is drawn under the loop and only while the loop is still
          // attached to the edge it is being pulled out of.
          if (style == PullStyle.goo)
            Positioned.fill(
              child: CustomPaint(
                painter: _GooPainter(
                  centreY: centre + kSpinnerSize / 2,
                  radius: size / 2 + kNeckHug,
                  attach: attach,
                  phase: turns,
                  working: working,
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: centre,
            child: Center(
              child: Opacity(
                opacity: working ? 1 : reach.clamp(0.0, 1.0),
                child: SizedBox.square(
                  dimension: kSpinnerSize,
                  child: Center(
                    child: SizedBox.square(
                      dimension: size,
                      child: CustomPaint(
                        painter: SpinnerPainter(
                          turns: turns,
                          // Faint until it would fire, so the mark is a change
                          // of colour as well as a bump.
                          color: colour,
                          // A circle on the way down, and the zig zag once
                          // there is work to show.
                          arc: working ? 1 : reach,
                          trace: trace,
                        ),
                      ),
                    ),
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

/// The goo the loop rides in: drawn out of the top edge, worked loose of it,
/// and taken back into it.
///
/// One body at every moment. While it is attached it leaves the edge at its
/// full width, necks down to a waist, and swells again round the loop. Once
/// it is clear it keeps breathing, because goo that held perfectly still
/// while the app was working would have set.
class _GooPainter extends CustomPainter {
  const _GooPainter({
    required this.centreY,
    required this.radius,
    required this.attach,
    required this.phase,
    required this.working,
  });

  /// Where the loop's own centre is, which is the middle of the body.
  final double centreY;

  /// How big that body is round the loop.
  final double radius;

  /// 1 while the goo is still part of the top edge, 0 once it is clear.
  final double attach;

  /// What turn the loop is on, which is what the breathing is timed to.
  final double phase;

  /// True while the app is working, when the goo breathes at its fullest.
  final bool working;

  @override
  void paint(Canvas canvas, Size size) {
    if (centreY <= 0 || radius <= 0) return;
    final x = size.width / 2;
    final paint = Paint()..color = AppColors.accent;
    final joined = attach.clamp(0.0, 1.0);
    if (joined > 0) {
      canvas.drawPath(_neck(x), paint);
    }
    canvas.drawPath(_body(x), paint);
  }

  /// The run of goo from the edge down to the body, waisted in the middle so
  /// the two read as one thing being pulled apart rather than as two shapes.
  Path _neck(double x) {
    final joined = attach.clamp(0.0, 1.0);
    final head = radius * (0.45 + 0.7 * joined);
    final waist = radius * (0.12 + 0.46 * joined);
    final meet = centreY - radius * 0.72;
    return Path()
      ..moveTo(x - head, 0)
      ..cubicTo(
        x - head,
        meet * 0.42,
        x - waist,
        meet * 0.34,
        x - waist,
        meet * 0.62,
      )
      ..cubicTo(
        x - waist,
        meet * 0.92,
        x - radius * 0.9,
        meet,
        x - radius,
        centreY,
      )
      ..lineTo(x + radius, centreY)
      ..cubicTo(
        x + radius * 0.9,
        meet,
        x + waist,
        meet * 0.92,
        x + waist,
        meet * 0.62,
      )
      ..cubicTo(x + waist, meet * 0.34, x + head, meet * 0.42, x + head, 0)
      ..close();
  }

  /// The body round the loop, breathing in and out.
  Path _body(double x) {
    final swell = kGooWobble * (working ? 1 : 0.45);
    final turn = phase * 2 * math.pi;
    final path = Path();
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final angle = i / steps * 2 * math.pi;
      final r = radius * (1 + swell * math.sin(kGooLobes * angle + turn));
      final point = Offset(
        x + math.cos(angle) * r,
        centreY + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_GooPainter old) =>
      old.centreY != centreY ||
      old.radius != radius ||
      old.attach != attach ||
      old.phase != phase ||
      old.working != working;
}
