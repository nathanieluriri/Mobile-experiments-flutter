import 'package:flutter/rendering.dart';

import '../theme/colors.dart';
import '../theme/metrics.dart';

/// How far a dog ear's nub sticks out of the strip, toward the sheet.
const kForeEdgeNub = 6.0;

/// How thick the bar marking where the reader is standing.
const kForeEdgePositionBar = 3.0;

/// Every twenty fifth hairline is drawn in [AppColors.inkFaint], which is what
/// turns a wall of pages into something countable.
const kForeEdgeCountEvery = 25;

/// How wide a match tick grows under a scrubbing thumb.
const kMatchTickScrubbed = 12.0;

/// The alpha every ordinary match tick is drawn at, so that a cluster reads as
/// density rather than as a row of separate marks.
const kMatchTickAlpha = 0.55;

/// The edge of the page block, drawn as the block itself: one hairline per
/// page, the reader's own position, the corners they have turned, and every
/// match the search found.
///
/// It is the app's only navigation control and it is 16 points wide, because
/// the map of a document is the document's own edge and nothing else needs to
/// be on screen for it.
class ForeEdgePainter extends CustomPainter {
  const ForeEdgePainter({
    required this.marks,
    required this.position,
    this.dogEars = const <double>[],
    this.damaged = const <double>[],
    this.matches = const <double>[],
    this.liveMatch,
    this.scrubbedMatch,
    this.matchOpacity = 1,
  });

  /// Where a hairline goes, each 0 at the start of the document and 1 at its
  /// end. One per page, per section, or per 25 rows.
  final List<double> marks;

  /// Where the reader is standing, 0 to 1.
  final double position;

  /// Every page whose corner is turned.
  final List<double> dogEars;

  /// Every page that would not open.
  final List<double> damaged;

  /// Every match the current query found.
  final List<double> matches;

  /// The match the chevrons are standing on.
  final double? liveMatch;

  /// The match under a scrubbing thumb, which widens so a reader can see what
  /// they are about to land on.
  final double? scrubbedMatch;

  /// How far the ticks have faded in, 0 to 1.
  final double matchOpacity;

  double _y(double fraction, Size size) =>
      (fraction.clamp(0, 1)) * (size.height - kPageRule);

  @override
  void paint(Canvas canvas, Size size) {
    _hairlines(canvas, size);
    _matches(canvas, size);
    for (final at in damaged) {
      canvas.drawRect(
        Rect.fromLTWH(0, _y(at, size), size.width, kPageRule),
        Paint()..color = AppColors.damage,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        _y(position, size) - kForeEdgePositionBar / 2,
        size.width,
        kForeEdgePositionBar,
      ),
      Paint()..color = AppColors.thread,
    );
    for (final at in dogEars) {
      canvas.drawRect(
        Rect.fromLTWH(
          -kForeEdgeNub,
          _y(at, size) - kForeEdgeNub / 2,
          kForeEdgeNub + size.width / 2,
          kForeEdgeNub,
        ),
        Paint()..color = AppColors.thread,
      );
    }
  }

  /// One hairline per unit, or a solid field once there are more units than
  /// there are points to draw them in. A hairline every third of a point is
  /// not a page block, it is noise.
  void _hairlines(Canvas canvas, Size size) {
    if (marks.isEmpty) return;
    if (marks.length >= size.height / 2) {
      canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.rule);
      return;
    }
    final rule = Paint()..color = AppColors.rule;
    final counted = Paint()..color = AppColors.inkFaint;
    for (var i = 0; i < marks.length; i++) {
      final every = (i + 1) % kForeEdgeCountEvery == 0;
      canvas.drawRect(
        Rect.fromLTWH(0, _y(marks[i], size), size.width, kPageRule),
        every ? counted : rule,
      );
    }
  }

  /// Match ticks, with anything closer together than [kMatchTickMerge] drawn
  /// once, so two hundred marks read as bands rather than as confetti.
  void _matches(Canvas canvas, Size size) {
    if (matches.isEmpty || matchOpacity <= 0) return;
    final ordinary = Paint()
      ..color = AppColors.marker.withValues(
        alpha: kMatchTickAlpha * matchOpacity,
      );
    var lastY = double.negativeInfinity;
    final sorted = List<double>.of(matches)..sort();
    for (final at in sorted) {
      final y = _y(at, size);
      if (y - lastY < kMatchTickMerge) continue;
      lastY = y;
      canvas.drawRect(
        Rect.fromLTWH(0, y - kMatchTick / 2, size.width, kMatchTick),
        ordinary,
      );
    }
    final scrubbed = scrubbedMatch;
    if (scrubbed != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          _y(scrubbed, size) - kMatchTickScrubbed / 2,
          size.width,
          kMatchTickScrubbed,
        ),
        Paint()..color = AppColors.marker.withValues(alpha: matchOpacity),
      );
    }
    final live = liveMatch;
    if (live != null) {
      final y = _y(live, size);
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          y - kMatchTickLive / 2 - kPageRule,
          size.width,
          kMatchTickLive + kPageRule * 2,
        ),
        Paint()..color = AppColors.leaf.withValues(alpha: matchOpacity),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y - kMatchTickLive / 2, size.width, kMatchTickLive),
        Paint()..color = AppColors.marker.withValues(alpha: matchOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(ForeEdgePainter old) =>
      old.marks != marks ||
      old.position != position ||
      old.dogEars != dogEars ||
      old.damaged != damaged ||
      old.matches != matches ||
      old.liveMatch != liveMatch ||
      old.scrubbedMatch != scrubbedMatch ||
      old.matchOpacity != matchOpacity;
}
