/// The highlighter sweep: what turns a list of offsets into a hand going over
/// the page with a marker.
///
/// Matches never appear pre highlighted, because a page that is already yellow
/// when you finish typing tells you nothing about where the word is. The
/// strokes are drawn in document order, one after another, so the eye is
/// carried down the page in the order it would read it.
library;

import 'package:flutter/widgets.dart';

import '../../../theme/colors.dart';
import '../../../theme/easings.dart';
import '../../../theme/metrics.dart';
import '../../../widgets/marked_text.dart';

/// How long the washes take to leave when a find is closed.
///
/// Longer than every other exit in the app, because it is the only one whose
/// job is to let a reader keep their place rather than to get out of the way.
const kFindFade = Duration(milliseconds: 200);

/// When each match is swept, and how far apart consecutive strokes start.
///
/// The stagger is compressed rather than dropped once a query has more matches
/// than [kSweepCap] can hold at the full 24 ms: past that the strokes crowd
/// together and the sweep reads as one wave, which is the honest picture of a
/// word that is everywhere. Compression begins above 17 visible matches,
/// because 17 gaps of 24 ms is the last span that still fits the cap.
class SweepSchedule {
  const SweepSchedule(this.count);

  /// A schedule with nothing to draw.
  static const SweepSchedule none = SweepSchedule(0);

  /// How many matches are being swept. Only the ones a reader can see are
  /// counted: a match off screen is already washed by the time it is scrolled
  /// to, so it must not lengthen the run or hold up a stroke that is visible.
  final int count;

  /// How long one stroke takes, in milliseconds.
  static const double strokeMs = 140;

  /// Milliseconds between the start of one stroke and the start of the next.
  double get staggerMs {
    if (count <= 1) return 0;
    final full = kSweepStagger.inMilliseconds.toDouble();
    final capped = kSweepCap.inMilliseconds / (count - 1);
    return capped < full ? capped : full;
  }

  /// Milliseconds from the first stroke starting to the last one starting.
  double get spanMs => count <= 1 ? 0 : staggerMs * (count - 1);

  /// The whole run, the last stroke's own 140 ms included. Ending at the cap
  /// instead would leave that stroke drawn part way across its word, which
  /// reads as a bug rather than as a highlighter.
  Duration get duration => count <= 0
      ? Duration.zero
      : Duration(milliseconds: (spanMs + strokeMs).round());

  /// When the stroke over the [index]th match begins.
  double startAt(int index) => index <= 0 ? 0 : staggerMs * index;

  /// How much of the [index]th stroke is drawn at [elapsedMs], 0 before it
  /// starts and 1 once the marker has crossed the whole word.
  double fillAt(int index, double elapsedMs) {
    if (index < 0 || index >= count) return 0;
    final t = ((elapsedMs - startAt(index)) / strokeMs).clamp(0.0, 1.0);
    return easeOutQuad.transform(t);
  }

  /// How far the second pass over the [index]th match has run at [elapsedMs].
  ///
  /// It begins only once that match's own stroke has finished, so the current
  /// match is never heavier than its neighbours before it is even drawn.
  double liveAt(int index, double elapsedMs) {
    if (index < 0 || index >= count) return 0;
    final from = startAt(index) + strokeMs;
    final t = ((elapsedMs - from) / kSweepLive.inMilliseconds).clamp(0.0, 1.0);
    return easeOutQuad.transform(t);
  }
}

/// One frame of the sweep: everything a painted match needs to know.
///
/// It is a value rather than a controller so a body can be rebuilt from it,
/// asserted against it, and captured at an exact millisecond.
@immutable
class SweepFrame {
  const SweepFrame({
    this.schedule = SweepSchedule.none,
    this.elapsedMs = 0,
    this.current = -1,
    this.liveFraction = 0,
    this.opacity = 1,
  });

  /// Nothing swept and nothing to sweep.
  static const SweepFrame idle = SweepFrame();

  final SweepSchedule schedule;

  /// How far the wash pass has run, in milliseconds.
  final double elapsedMs;

  /// Which match the chevrons are standing on, or -1 for none.
  final int current;

  /// How far the current match's second pass has run, 0 to 1.
  final double liveFraction;

  /// How opaque every wash is, which is what fades them out on closing rather
  /// than snapping them off under the eye that was following them.
  final double opacity;

  /// How much of the stroke over the [ordinal]th match is drawn.
  double fillOf(int ordinal) => schedule.fillAt(ordinal, elapsedMs);

  /// The wash under the [ordinal]th match: [AppColors.foundWash] ordinarily,
  /// lerped toward [AppColors.foundLive] for the one being stood on.
  ///
  /// Two alphas of one hue rather than two hues, so a page carrying two
  /// hundred marks reads as density and never as confetti.
  Color colorOf(int ordinal) {
    final live = ordinal == current ? liveFraction : 0.0;
    final base = Color.lerp(AppColors.foundWash, AppColors.foundLive, live)!;
    if (opacity >= 1) return base;
    return base.withValues(alpha: base.a * opacity.clamp(0.0, 1.0));
  }

  /// How far the fore edge's match ticks have faded in.
  ///
  /// They arrive with the sweep rather than before it, so the rail and the
  /// page agree about the moment the document was searched.
  double get railOpacity {
    if (schedule.count <= 0) return 0;
    final t = (elapsedMs / kRailFade.inMilliseconds).clamp(0.0, 1.0);
    return easeOutQuad.transform(t) * opacity.clamp(0.0, 1.0);
  }
}

/// Which pass the one controller is running.
enum SweepPhase {
  /// The strokes going over the page in document order.
  wash,

  /// A single match becoming the current one, after a chevron step.
  relight,

  /// Every wash leaving together.
  fade,
}

/// The whole highlighter, on one [AnimationController].
///
/// One controller with a per match phase offset, never one controller per
/// word: two hundred controllers would be two hundred tickers for an effect
/// that is over in four hundred milliseconds, and no test could pump them to
/// an exact frame.
class MatchSweep extends ChangeNotifier {
  MatchSweep({required TickerProvider vsync})
    : _drive = AnimationController(vsync: vsync, duration: Duration.zero) {
    _drive.addListener(notifyListeners);
  }

  final AnimationController _drive;

  SweepSchedule _schedule = SweepSchedule.none;
  SweepPhase _phase = SweepPhase.wash;
  int _current = -1;

  /// The schedule the current query is running on.
  SweepSchedule get schedule => _schedule;

  /// Which match the chevrons are standing on, or -1 when there is none.
  int get current => _current;

  /// The frame a body should paint right now.
  SweepFrame get frame {
    switch (_phase) {
      case SweepPhase.wash:
        final elapsed = _drive.value * _schedule.duration.inMilliseconds;
        return SweepFrame(
          schedule: _schedule,
          elapsedMs: elapsed,
          current: _current,
          liveFraction: _schedule.liveAt(_current, elapsed),
        );
      case SweepPhase.relight:
        return SweepFrame(
          schedule: _schedule,
          elapsedMs: _settledMs,
          current: _current,
          liveFraction: _drive.value,
        );
      case SweepPhase.fade:
        return SweepFrame(
          schedule: _schedule,
          elapsedMs: _settledMs,
          current: _current,
          liveFraction: 1,
          opacity: 1 - _drive.value,
        );
    }
  }

  /// A time past the end of the run, so every stroke reads as finished.
  double get _settledMs =>
      _schedule.duration.inMilliseconds.toDouble() + SweepSchedule.strokeMs;

  /// Runs the sweep for a query with [visibleCount] matches on screen,
  /// standing on [current].
  ///
  /// A query with nothing to show still resets the controller, because the
  /// washes of the last query must not survive the keystroke that killed them.
  void sweep(int visibleCount, {int current = 0}) {
    _schedule = SweepSchedule(visibleCount);
    _current = visibleCount <= 0 ? -1 : current.clamp(0, visibleCount - 1);
    _phase = SweepPhase.wash;
    _drive.duration = _schedule.duration;
    if (_schedule.count <= 0) {
      _drive.value = 0;
      notifyListeners();
      return;
    }
    _drive.forward(from: 0);
  }

  /// Moves the live pass to [index] without washing the page again, which is
  /// what a chevron step does: the marks are already there, and only the one
  /// being stood on changes weight.
  void relight(int index) {
    if (_schedule.count <= 0) return;
    _current = index.clamp(0, _schedule.count - 1);
    _phase = SweepPhase.relight;
    _drive.duration = kSweepLive;
    _drive.forward(from: 0);
  }

  /// Takes every wash off the page over [kFindFade], so the eye can follow
  /// where it had got to instead of losing the place to a hard cut.
  void fade() {
    if (_schedule.count <= 0) {
      _schedule = SweepSchedule.none;
      _current = -1;
      notifyListeners();
      return;
    }
    _phase = SweepPhase.fade;
    _drive.duration = kFindFade;
    _drive.forward(from: 0);
  }

  /// Drops the query with no animation, for when the find layer is torn down
  /// rather than closed.
  void clear() {
    _schedule = SweepSchedule.none;
    _current = -1;
    _phase = SweepPhase.wash;
    _drive.duration = Duration.zero;
    _drive.value = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _drive.dispose();
    super.dispose();
  }
}

/// One match inside a run of text, and where it falls in the sweep's order.
///
/// The ordinal is assigned by whatever is painting the page rather than by the
/// search, because the sweep runs over the matches a reader can see and only
/// the body knows which those are.
@immutable
class SweptRange {
  const SweptRange({
    required this.start,
    required this.end,
    required this.ordinal,
  });

  /// Character offsets inside the run's own text.
  final int start;
  final int end;

  /// Position in the sweep, counted in document order over visible matches.
  final int ordinal;
}

/// A line of document text with the query's matches swept under it.
///
/// It is the house [MarkedText] driven from a [SweepFrame] rather than a new
/// render object: the marker stroke, its lean and its overhang are already
/// family behaviour, and a highlighter that drew a plain rectangle here would
/// be the one mark in the app that did not look hand made.
class SweptText extends StatelessWidget {
  const SweptText(
    this.text, {
    super.key,
    required this.style,
    required this.ranges,
    required this.frame,
    this.maxLines,
    this.ellipsis,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;

  /// Every match inside [text], with its place in the sweep.
  final List<SweptRange> ranges;

  final SweepFrame frame;
  final int? maxLines;
  final String? ellipsis;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return MarkedText(
      text,
      style: style,
      markerColor: AppColors.foundWash,
      marks: <TextMark>[
        for (final range in ranges)
          TextMark(
            start: range.start,
            end: range.end,
            fill: frame.fillOf(range.ordinal),
            color: frame.colorOf(range.ordinal),
          ),
      ],
      maxLines: maxLines,
      ellipsis: ellipsis,
      textAlign: textAlign,
    );
  }
}
