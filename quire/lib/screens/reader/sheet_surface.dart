import 'package:flutter/widgets.dart';

import '../../helpers/fold_geometry.dart';
import '../../theme/colors.dart';
import '../../theme/edges.dart';
import '../../theme/metrics.dart';
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

  /// Makes whatever [buildBack] needs ready, called the moment a fold arms and
  /// before the corner has moved a point.
  ///
  /// A body whose back is already built from what it is holding does nothing
  /// here. A body that has to go and read something, which is the page file,
  /// reads it now: the sheet is committed to having two sides, so the second
  /// side cannot be a thing the app starts looking for once the paper is
  /// already turning.
  void prepareBack() {}

  /// Pages for a PDF, sections for prose, rows for a grid. It is the scale the
  /// fore edge is drawn against.
  int get unitCount;

  /// What the folio chip prints: `4 / 6`, `24 / 73`, `38%`.
  String get positionLabel;

  /// Where the fore edge draws a hairline, each 0 at the top of the document
  /// and 1 at its end. One per page, per section, or per 25 rows.
  List<double> get foreEdgeMarks;

  /// Where the document would not open, on the same 0 to 1 scale.
  ///
  /// Only a format that decides a rung per unit has any: a page file knows
  /// which of its pages threw, while a parse either produced a document or did
  /// not, and a whole document that failed is the torn sheet rather than a
  /// tick on the strip.
  List<double> get damagedMarks => const <double>[];

  /// True when the body answers a finger all the way to the sheet's right
  /// edge.
  ///
  /// A grid does: its last spines stand under the fore edge's hit strip, and a
  /// strip that accepts a pointer outright would leave those columns with no
  /// way to be opened. The shell narrows the strip to the desk beside the
  /// sheet for a body that says so.
  bool get ownsRightEdge => false;

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
/// corner, the hairline that tells it from the desk, and the fold that corner
/// carries.
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

  @override
  Widget build(BuildContext context) {
    final showing = side == SheetSide.front ? front : back;
    final hidden = side == SheetSide.front ? back : front;
    return SizedBox(
      width: kSheetWidth,
      height: kSheetHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: kPeelableCorner,
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
              // The face carries the sheet's rule rather than the sheet
              // carrying it, so the hairline lands over a grid that paints its
              // own header out to the edge, and still disappears where the
              // corner turns down.
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  showing,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: kPeelableCorner,
                          border: AppEdges.all(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
