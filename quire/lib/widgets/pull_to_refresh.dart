import 'dart:async';

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
  double get _shown => _working
      ? kPullRest * (1 - easeOutCubic.transform(_leave.value))
      : _pull;

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
          final loop = _Loop(
            down: down,
            // Before it is working the loop is a readout of the pull, and
            // after it is a loop.
            turns: _working ? _turn.value : reach * kPullTurns,
            reach: reach,
            working: _working,
            trace: _working ? _trace.value : 0,
            style: widget.style,
          );
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
    required this.style,
  });

  /// How far the crinkle has travelled round the ring.
  final double trace;

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
    final held = style == PullStyle.goo && !working && reach < 1;
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
      PullStyle.overlay || PullStyle.goo =>
        (down - kSpinnerSize / 2).clamp(0.0, kPullLimit),
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
                painter: _NeckPainter(
                  centreY: centre + kSpinnerSize / 2,
                  radius: size / 2,
                  gone: working ? 1 : reach,
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

/// The drop of goo the loop is being pulled out of the top edge in.
///
/// One body rather than a run of circles: it leaves the edge at its full
/// width, narrows to a waist, and swells again round the loop, which rides
/// inside it until the pull reaches the mark and the neck lets go. It is the
/// app's own material, in [AppColors.accent], the same goo the menu's pills
/// are peeled off the dots on.
class _NeckPainter extends CustomPainter {
  const _NeckPainter({
    required this.centreY,
    required this.radius,
    required this.gone,
  });

  /// Where the loop's own centre is, which is where the drop ends.
  final double centreY;

  /// The loop's radius, which is what the drop swells to round it.
  final double radius;

  /// 0 at the edge and 1 at the mark, where the neck has thinned to nothing
  /// and the loop is clear of it.
  final double gone;

  @override
  void paint(Canvas canvas, Size size) {
    final left = 1 - gone.clamp(0.0, 1.0);
    if (left <= 0 || centreY <= 0) return;
    final x = size.width / 2;
    final head = radius * 1.15;
    final hold = radius + kNeckHug;
    // The waist is what thins as the pull goes on, so the drop necks down
    // before it lets go rather than simply fading out.
    final waist = radius * (0.24 + 0.5 * left);
    final path = Path()
      ..moveTo(x - head, 0)
      ..cubicTo(
        x - head,
        centreY * 0.34,
        x - waist,
        centreY * 0.32,
        x - waist,
        centreY * 0.55,
      )
      ..cubicTo(
        x - waist,
        centreY - hold * 0.9,
        x - hold,
        centreY - hold * 0.8,
        x - hold,
        centreY,
      )
      ..arcToPoint(
        Offset(x + hold, centreY),
        radius: Radius.circular(hold),
        clockwise: false,
      )
      ..cubicTo(
        x + hold,
        centreY - hold * 0.8,
        x + waist,
        centreY - hold * 0.9,
        x + waist,
        centreY * 0.55,
      )
      ..cubicTo(
        x + waist,
        centreY * 0.32,
        x + head,
        centreY * 0.34,
        x + head,
        0,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_NeckPainter old) =>
      old.centreY != centreY || old.radius != radius || old.gone != gone;
}
