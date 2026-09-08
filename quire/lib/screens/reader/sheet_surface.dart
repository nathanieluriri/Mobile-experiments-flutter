import 'package:flutter/widgets.dart';

import '../../helpers/fold_geometry.dart';
import '../../theme/colors.dart';
import '../../theme/metrics.dart';
import '../../theme/shadows.dart';
import 'corner_peel.dart';

/// The reading sheet's rectangle on screen.
///
/// It never moves, in any format and in any state, which is what lets the fore
/// edge, the folio chip and the placement layer be laid out as constants
/// rather than measured from whatever the document happens to be.
const kSheetRect = Rect.fromLTWH(
  kSheetLeft,
  kSheetTop,
  kSheetWidth,
  kSheetHeight,
);

/// Which face of the sheet is showing.
enum SheetSide {
  front,
  back;

  /// The corner the resting fold sits in.
  ///
  /// The front folds at the bottom right; once turned over, the same physical
  /// corner is at the top left, so that is where the fold reappears.
  Corner get restCorner =>
      this == SheetSide.front ? Corner.bottomRight : Corner.topLeft;
}

/// The one thing the reader shell knows about a document.
///
/// Every format implements it, which is what lets the shell paint the fore
/// edge, the folio chip and the back of the page without knowing whether it is
/// holding a PDF, a Word file or a spreadsheet. A body is a widget so it can
/// be handed straight to the sheet; the two build methods exist because a
/// sheet has two sides and the shell decides which one is up.
abstract class ReaderBody extends StatelessWidget {
  const ReaderBody({super.key});

  /// What the document shows you.
  Widget buildFront(BuildContext context);

  /// What the document actually holds: the extracted text of a page, the raw
  /// source of a Markdown file, the stored values behind formatted cells.
  Widget buildBack(BuildContext context);

  /// Pages for a PDF, sections for prose, rows for a grid. It is the scale the
  /// fore edge is drawn against.
  int get unitCount;

  /// What the folio chip prints: `4 / 6`, `24 / 73`, `38%`.
  String get positionLabel;

  /// Where the fore edge draws a hairline, each 0 at the top of the document
  /// and 1 at its end. One per page, per section, or per 25 rows.
  List<double> get foreEdgeMarks;

  @override
  Widget build(BuildContext context) => buildFront(context);
}

/// The layer a signature is placed on: above the sheet, below the chrome.
///
/// The shell owns where it sits and what it sits between, and it is empty
/// until something is being placed on the page. Keeping the slot in the shell
/// rather than in the signature flow is what stops a placed mark from ending
/// up under the fore edge or over the head band.
class PlacementSlot extends StatelessWidget {
  const PlacementSlot({super.key, this.child});

  /// What is being placed, or null when nothing is.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final placed = child;
    if (placed == null) return const SizedBox.expand();
    return SizedBox.expand(child: placed);
  }
}

/// The 372 x 714 leaf the whole reader is built on: its fill, its one square
/// corner, its contact shadow, and the fold that corner carries.
///
/// The sheet clips its own content, so a page that is taller than the leaf
/// scrolls inside it rather than over the desk, and the fold is drawn last so
/// it lifts off whatever the body is showing.
class SheetSurface extends StatelessWidget {
  const SheetSurface({
    super.key,
    required this.front,
    required this.back,
    this.side = SheetSide.front,
    this.foldPoint,
    this.restInset = kFoldRestInset,
    this.caught = false,
    this.shadows,
  });

  /// The face that is up.
  final Widget front;

  /// The face underneath, uncovered by the fold.
  final Widget back;

  final SheetSide side;

  /// Where the corner has been pulled to, in sheet coordinates, or null when
  /// the fold is sitting at [restInset].
  final Offset? foldPoint;

  final double restInset;

  /// True once a dog ear has caught, which lights the fold line.
  final bool caught;

  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final showing = side == SheetSide.front ? front : back;
    final hidden = side == SheetSide.front ? back : front;
    return Container(
      width: kSheetWidth,
      height: kSheetHeight,
      decoration: BoxDecoration(
        color: AppColors.leaf,
        borderRadius: kPeelableCorner,
        boxShadow: shadows ?? AppShadows.leafRest(),
      ),
      child: ClipRRect(
        borderRadius: kPeelableCorner,
        // A body starts at the sheet's own top edge. Without this it would
        // inherit the screen's safe area as content padding and every format
        // would begin 62 points down its own page.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: CornerPeel(
            corner: side.restCorner,
            point: foldPoint,
            restInset: restInset,
            caught: caught,
            back: hidden,
            child: showing,
          ),
        ),
      ),
    );
  }
}
