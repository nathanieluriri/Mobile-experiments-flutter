import 'package:flutter/widgets.dart';

import '../../../helpers/tear_path.dart';
import '../../../painting/tear_painter.dart';
import '../../../theme/colors.dart';
import '../../../theme/metrics.dart';
import '../../../theme/typography.dart';
import '../../../widgets/shimmer.dart';

/// What is left where an image this reader cannot turn into pixels was.
///
/// It is written out in full rather than produced by a transform, so a golden
/// reads what this file says.
const String kImageLabel = 'IMAGE';

/// What a page that would not interpret prints across itself.
const String kPageDamagedLabel = 'THIS PAGE WILL NOT OPEN';

/// What a file that opened and parsed, and turned out to hold nothing at all,
/// prints across the sheet.
///
/// It is said on both faces. A file with nothing in it has nothing on its
/// back either, and turning the corner of one has to uncover the same answer
/// rather than blank paper.
const String kDocumentEmptyLabel = 'THIS FILE IS EMPTY';

/// How wide the scan card is, from section 11.7.
const double kScanCardWidth = 320.0;

/// How dark a mark this app makes on a rendered page is drawn.
///
/// A rendered PDF page is white, because it is a white page. Every grey in
/// this palette is mixed for a dark ground and none of them belong on paper,
/// so anything the app itself prints onto a page is [AppColors.pageInk] held
/// back rather than a grey of its own. Held back this far it lands about
/// where the dark ground's own faint ink lands against the dark ground: quiet
/// enough that the document stays the loudest thing on the sheet, legible
/// enough to be read on purpose.
const double kPaperMarkAlpha = 0.55;

/// How dark a rule this app draws on a rendered page is.
///
/// A rule says where something was. It is not meant to be read, so it sits
/// well under a mark.
const double kPaperRuleAlpha = 0.22;

/// How much of a torn page is missing, and how far its label sits above the
/// tear. Both are the damaged sheet's own numbers, so a torn page inside a
/// document and a torn document read as the same accident.
const double kPageTearFraction = kTearFraction;

/// The outline an image leaves behind when this reader cannot decode it.
///
/// A hole a reader cannot account for is worse than a missing picture: the
/// rect says the page really does carry something here, and that the file, not
/// the layout, is what stopped it being shown.
class UnsupportedImageBox extends StatelessWidget {
  const UnsupportedImageBox({
    super.key,
    this.label = kImageLabel,
    this.onPage = false,
  });

  final String label;

  /// True when the box is drawn onto a rendered PDF page, which is white.
  ///
  /// The same hole appears in a reflowed document and on a rendered page, and
  /// the two grounds are opposite, so the box has to know which paper it is
  /// printed on. A dark ground's rule on white reads as a hard black box; a
  /// dark ground's faint ink on white barely reads at all.
  final bool onPage;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: onPage
              ? AppColors.pageInk.withValues(alpha: kPaperRuleAlpha)
              : AppColors.hairline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(kLeafRadius),
      ),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.micro.copyWith(
            color: onPage
                ? AppColors.pageInk.withValues(alpha: kPaperMarkAlpha)
                : AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

/// The card a page that is a picture this reader cannot read puts up. The
/// caller places it: on a page it sits in the middle of the page.
///
/// It is a statement, not an error: the page is a photograph of paper, so
/// there is nothing on it to render and nothing in it to find, and saying so
/// is more use than a blank sheet or an apology.
class ScanCard extends StatelessWidget {
  const ScanCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kScanCardWidth,
      padding: const EdgeInsets.all(kSpace20),
      decoration: BoxDecoration(
        // The card stands on the sheet the unreadable page left behind, so it
        // takes the value above it. A card in the sheet's own colour would be
        // a hairline drawn on nothing.
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(kLeafRadius),
        border: Border.all(color: AppColors.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SCANNED PAGE',
            style: AppText.micro.copyWith(color: AppColors.inkFaint),
          ),
          const SizedBox(height: kSpace8),
          Text(
            'This page is a picture.',
            style: AppText.title.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: kSpace8),
          Text(
            'Nothing on it can be read or found.',
            style: AppText.bodyTight.copyWith(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// A page that has not been interpreted yet: its real rectangle, at its real
/// size, with a band of light crossing it.
///
/// The rectangle is the point. The page block is laid out from the page tree
/// before any content stream is run, so nothing moves when the words arrive,
/// and a reader who scrolls into a page that is still being read never has the
/// text jump out from under them. There is no spinner anywhere in this app.
class PageShimmer extends StatelessWidget {
  const PageShimmer({super.key, required this.size, required this.progress});

  final Size size;

  /// 0 to 1 across one sweep, from a controller a test can pump.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: ClipRect(
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: AppColors.surfaceHigh)),
            Shimmer(
              progress: progress,
              width: size.width,
              height: size.height,
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of a document that would not open, torn out of an otherwise
/// readable block.
///
/// Partial damage never takes over. A file whose fourth page throws still
/// reads everywhere else, so the damage is drawn at page size and in page
/// place, and the reader keeps scrolling past it.
class TornPage extends StatelessWidget {
  TornPage({super.key, required this.size, this.label = kPageDamagedLabel})
    : _tear = tearPolyline(size.width, size.height * kPageTearFraction);

  final Size size;
  final String label;

  /// Built once with the page, never per frame: a tear that reshuffled while
  /// you looked at it would read as static rather than as paper.
  final List<Offset> _tear;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: TearPainter(tear: _tear, backColor: AppColors.leafBack),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: size.height * kPageTearFraction - kSpace40,
            child: Center(
              child: Text(
                label,
                style: AppText.micro.copyWith(color: AppColors.damage),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
