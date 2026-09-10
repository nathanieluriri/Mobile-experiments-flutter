import 'dart:async';

import 'package:flutter/widgets.dart';

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
const kPullRest = 44.0;

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
  });

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

  @override
  void initState() {
    super.initState();
    _turn = AnimationController(vsync: this, duration: kSpinnerPeriod);
    _leave = AnimationController(vsync: this, duration: kPullRetract);
  }

  @override
  void dispose() {
    _turn.dispose();
    _leave.dispose();
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
    if (notification is ScrollUpdateNotification && _pull > 0) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 0) _setPull((_pull - delta).clamp(0.0, kPullLimit));
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
    _turn.repeat();
    Feel.commit.ring();
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        await Future<void>.delayed(kPullHold);
        if (mounted) await _leave.forward();
        _turn.stop();
        if (mounted) {
          setState(() {
            _working = false;
            _pull = 0;
            _armed = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: widget.child),
          if (_pull > 0 || _working)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[_turn, _leave]),
                  builder: (context, _) => _Loop(
                    down: _shown,
                    // Before it is working the loop is a readout of the pull,
                    // and after it is a loop.
                    turns: _working
                        ? _turn.value
                        : (_pull / kPullThreshold).clamp(0.0, 1.0) * kPullTurns,
                    reach: (_pull / kPullThreshold).clamp(0.0, 1.0),
                    working: _working,
                  ),
                ),
              ),
            ),
        ],
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
  });

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
    return Padding(
      padding: EdgeInsets.only(
        top: (down - kSpinnerSize / 2).clamp(0.0, kPullLimit),
      ),
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
                    // Faint until it would fire, so the mark is a change of
                    // colour as well as a bump.
                    color: working || reach >= 1
                        ? AppColors.accentBright
                        : AppColors.inkFaint,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
