import 'package:flutter/widgets.dart';

import '../../painting/fore_edge_painter.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
import '../../theme/typography.dart';

/// How tall the bubble that follows a scrubbing thumb is.
const kForeEdgeBubble = 44.0;

/// How far the bubble sits to the left of the strip, so the thumb never
/// covers the number it is asking for.
const kForeEdgeBubbleGap = 8.0;

/// How much of the strip's own travel one page occupies before the reader has
/// to move a whole page. One page per 2.6 points of travel, from section 12.7.
const kForeEdgePointsPerUnit = 2.6;

/// Which unit a scrub at [y] points down the strip has landed on, for a
/// document of [unitCount] units starting from [from].
///
/// The travel rate is fixed rather than proportional to the document, so a
/// long file scrolls past under the thumb at the same speed a short one does
/// and the gesture always feels like the same gesture.
int scrubTarget(int from, double dy, int unitCount) {
  if (unitCount <= 0) return 0;
  final moved = (dy / kForeEdgePointsPerUnit).round();
  return (from + moved).clamp(0, unitCount - 1);
}

/// The edge of the page block: the app's only navigation control.
///
/// The strip runs the sheet's full height so a tick maps one to one onto the
/// document, while its hit region stops 72 points short of the bottom, which
/// is what gives the corner peel a corner to own.
class ForeEdge extends StatelessWidget {
  const ForeEdge({
    super.key,
    required this.marks,
    required this.position,
    this.dogEars = const <double>[],
    this.damaged = const <double>[],
    this.signatures = const <double>[],
    this.matches = const <double>[],
    this.liveMatch,
    this.scrubbedMatch,
    this.matchOpacity = 1,
  });

  final List<double> marks;
  final double position;
  final List<double> dogEars;
  final List<double> damaged;
  final List<double> signatures;
  final List<double> matches;
  final double? liveMatch;
  final double? scrubbedMatch;
  final double matchOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kForeEdgeWidth,
      height: kForeEdgeHeight,
      child: CustomPaint(
        painter: ForeEdgePainter(
          marks: marks,
          position: position,
          dogEars: dogEars,
          damaged: damaged,
          signatures: signatures,
          matches: matches,
          liveMatch: liveMatch,
          scrubbedMatch: scrubbedMatch,
          matchOpacity: matchOpacity,
        ),
      ),
    );
  }
}

/// The bubble that follows a thumb down the fore edge.
///
/// It carries the position a reader is about to land on, and the number of
/// matches on it when a search is live, so a scrub through a long document is
/// a search result in itself.
class ForeEdgeBubble extends StatelessWidget {
  const ForeEdgeBubble({super.key, required this.label, this.matches});

  /// What the bubble prints, already formed: `p. 4 / 6`.
  final String label;

  /// How many matches sit on the unit under the thumb, or null when nothing
  /// is being searched for.
  final int? matches;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kForeEdgeBubble,
      padding: const EdgeInsets.symmetric(horizontal: kSpace14),
      decoration: BoxDecoration(
        // Chrome, so a control fill and a hairline, never the sheet's own
        // value: the bubble travels the length of the page and would vanish
        // into the paper for most of that trip.
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kPillRadius),
        border: AppEdges.all(context),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: AppText.folio.copyWith(color: AppColors.ink)),
          if (matches != null)
            Text(
              '$matches MARKS',
              style: AppText.micro.copyWith(color: AppColors.inkFaint),
            ),
        ],
      ),
    );
  }
}
