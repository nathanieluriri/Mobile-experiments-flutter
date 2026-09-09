import 'package:flutter/painting.dart';

// Section 6.1, the spacing scale. Base 4. Nothing outside these steps.
const kSpace4 = 4.0;
const kSpace8 = 8.0;
const kSpace12 = 12.0;
const kSpace14 = 14.0;
const kSpace16 = 16.0;
const kSpace20 = 20.0;
const kSpace24 = 24.0;
const kSpace26 = 26.0;
const kSpace32 = 32.0;
const kSpace40 = 40.0;
const kSpace56 = 56.0;

/// The one spacing scale, in order, for anything that needs to walk it.
const kSpacingScale = <double>[
  kSpace4,
  kSpace8,
  kSpace12,
  kSpace14,
  kSpace16,
  kSpace20,
  kSpace24,
  kSpace26,
  kSpace32,
  kSpace40,
  kSpace56,
];

// Section 6.2, screen and desk.
const kScreenWidth = 402.0;
const kScreenHeight = 874.0;
const kSafeTop = 62.0;
const kSafeBottom = 34.0;
const kScreenPadding = 20.0;
const kDeskHeaderTop = 62.0;

/// The header occupies y 62 to 118.
const kDeskHeaderHeight = 56.0;
const kChipRowTop = 124.0;
const kChipHeight = 30.0;
const kChipGap = 10.0;
const kChipPaddingX = 11.0;
const kChipUnderlineHeight = 2.0;

/// How far the selected chip's underline sits below the label's baseline box.
const kChipUnderlineGap = 6.0;
const kCardListTop = 176.0;

/// 20 + 362 + 20 = 402.
const kCardWidth = 362.0;
const kCardHeight = 96.0;
const kCardGap = 12.0;
const kCardPadding = 14.0;

/// 14 of padding, then the 30 wide mark, then a 14 gap.
const kCardTextLeft = 58.0;

/// The card's own resting fold, bottom right.
const kCardFoldRestInset = 16.0;
const kCardProgressWidth = 120.0;
const kCardProgressHeight = 2.0;

/// The type mark is square, and the one in a list row is this big.
const kTypeMarkSize = 30.0;

/// The same mark on a grid card, where it shares a 44 tall header with a two
/// line title.
const kTypeMarkGridSize = 20.0;

/// The mark's corner, at [kTypeMarkSize]. It scales with the mark, so the
/// shape is the same object at both sizes rather than two different squircles.
const kTypeMarkRadius = 8.0;

/// Where the letters' 12 tall line box sits inside a [kTypeMarkSize] mark, so
/// a painter that lays them out by hand centres them exactly where the widget
/// does.
const kTypeMarkLettersTop = 9.0;

const kColophonRuleWidth = 120.0;

/// What makes the collapse reachable: six cards plus the colophon plus this
/// padding stand taller than the viewport, so the small title range completes.
const kDeskListBottomPadding = 130.0;
const kHeaderButtonSize = 38.5;
const kHeaderButtonRadius = 14.0;

// Scroll ranges, copied from the family so the collapse timing matches.
const kSmallTitleRange = (22.0, 58.0);
const kLargeTitleRange = (0.0, 44.0);
const kOverscrollRange = (-80.0, 0.0);
const kOverscrollScale = 1.08;
const kTitleShift = 8.0;

/// Where [value] sits inside [range], as 0 to 1.
double rangeProgress(double value, (double, double) range) {
  final (start, end) = range;
  return ((value - start) / (end - start)).clamp(0, 1);
}

// Section 6.3, the reader. The reading sheet is one rectangle, the same in
// every format and every golden.
const kSheetLeft = 12.0;

/// Clears the head band.
const kSheetTop = 118.0;
const kSheetWidth = 372.0;

/// Bottom edge at y 832, 8 above the safe area.
const kSheetHeight = 714.0;

/// Prose only.
const kSheetPadding = 26.0;

/// 372 - 2 x 26.
const kProseMeasure = 320.0;
const kHeadBandTop = 62.0;

/// y 62 to 114.
const kHeadBandHeight = 52.0;

/// Abuts the sheet's right edge.
const kForeEdgeLeft = 384.0;

/// Drawn x 384 to 400, with 2 of ground to the screen edge.
const kForeEdgeWidth = 16.0;
const kForeEdgeTop = 118.0;

/// Exactly the sheet's height, so a tick maps 1:1.
const kForeEdgeHeight = 714.0;

/// A 42pt wide hit region.
const kForeEdgeHitLeft = 360.0;

/// Stops 72 above the sheet bottom so the corner wins.
const kForeEdgeHitBottom = 760.0;

/// x 312 to 384, y 760 to 832.
const kCornerHandle = 72.0;

/// The reading sheet's resting fold.
const kFoldRestInset = 16.0;

/// House value. Keeps the fold geometry from degenerating at the edge.
const kFoldEdgeMargin = 4.0;

/// Where a caught dog ear settles.
const kDogEarInset = 14.0;

/// Of the flip commit distance.
const kDogEarCatchFraction = 0.6;

/// Of the way to the opposite corner.
const kFlipCommitFraction = 0.55;
const kFolioChipWidth = 76.0;
const kFolioChipHeight = 30.0;

/// From the sheet's right and bottom edges.
const kFolioChipInset = 12.0;

/// The hairline between two PDF pages.
const kPageRule = 1.0;
const kBackDragCommit = 96.0;

/// Points per second.
const kBackDragVelocity = 400.0;

/// A back drag must start inside x below this.
const kBackEdgeZone = 24.0;

// Section 6.4, the sheet body.
const kRowHeaderWidth = 40.0;
const kSpineWidth = 12.0;
const kSpineWidthMax = 28.0;
const kOpenColumnMin = 160.0;
const kOpenColumnMax = 272.0;
const kTableHeaderHeight = 32.0;
const kTableRowHeight = 30.0;
const kCellPaddingX = 8.0;
const kSheetTabHeight = 28.0;
const kParseStripHeight = 20.0;
const kCellBarHeight = 40.0;
const kSpineBarMax = 10.0;
const kSpineBarHeight = 2.0;
const kSpineDot = 4.0;

/// Every fifth row carries the leader rule rather than the faint one.
const kLeaderEvery = 5;

/// Width of the one open column, and of each spine, for a sheet of [columns]
/// columns. Total always equals kSheetWidth when the sheet fits, and overflows
/// into a horizontal scroll when it does not.
({double open, double spine}) columnWidths(int columns) {
  final spines = columns - 1;
  const avail = kSheetWidth - kRowHeaderWidth; // 332
  if (spines <= 0) return (open: avail, spine: 0);
  var spine = kSpineWidth;
  var open = avail - spines * spine;
  if (open > kOpenColumnMax) {
    spine =
        ((avail - kOpenColumnMax) / spines).clamp(kSpineWidth, kSpineWidthMax);
    open = avail - spines * spine;
  }
  return (open: open.clamp(kOpenColumnMin, avail), spine: spine);
}

// Section 6.5, find, riffle, dock, sign.
const kFindFieldHeight = 38.5;
const kStatusRowHeight = 22.0;
const kChevronSize = 32.0;
const kMatchTick = 2.0;
const kMatchTickLive = 4.0;

/// Ticks closer than this merge into one.
const kMatchTickMerge = 3.0;
const kRiffleSlotHeight = 132.0;
const kRiffleThumbWidth = 84.0;
const kRiffleThumbHeight = 108.0;
const kRiffleScrimOpacity = 0.88;
const kRiffleThumbScale = 84.0 / 372.0;

/// A run under this effective size becomes a bar.
const kRiffleCollapseBelow = 6.0;
const kArcRadius = 520.0;
const kMaxTiltDeg = 14.0;
const kItemTiltInfluence = 0.2;
const kMaxScaleShrink = 0.12;
const kCenterDistanceClamp = 1.2;
const kTopFadeHeight = 96.0;
const kBottomFadeHeight = 160.0;
const kBottomGradientHeight = 56.0;
const kDockGap = 18.0;
const kDockButtonSize = 54.0;
const kDockButtonSpacing = 78.0;
const kDockHoverScale = 1.18;
const kDockHoverRadius = kDockButtonSize * 0.85;
const kDockEnterRise = 25.0;
const kPadLeft = 20.0;
const kPadTop = 150.0;
const kPadWidth = 362.0;
const kPadHeight = 240.0;
const kPadBaselineFraction = 0.70;
const kStampInitialWidth = 200.0;
const kStampScaleMin = 0.5;
const kStampScaleMax = 1.8;
const kBaselineSnapDistance = 4.0;
const kChromeDimAmount = 0.78;
const kDimmedCardOpacity = 0.25;
const kLiftScaleDelta = 0.02;
const kPlacementDim = 0.86;
const kShimmerBand = 96.0;
const kShimmerOpacity = 0.28;
const kShimmerSkew = 14.0;

// Section 6.6, radii.

/// Paper barely rounds. 12 would make a sheet read as a card.
const kLeafRadius = 3.0;

/// Anything that carries a peel handle. A folded corner cannot be rounded, and
/// this one asymmetry is the app's tell.
const kPeelableCorner = BorderRadius.only(
  topLeft: Radius.circular(kLeafRadius),
  topRight: Radius.circular(kLeafRadius),
  bottomLeft: Radius.circular(kLeafRadius),
);

/// Shelf chips, sheet tabs.
const kChipRadius = 8.0;

/// The search field, and every 38.5 header button.
const kFieldRadius = 14.0;

/// The folio chip, the undo pill, the commit pill.
const kPillRadius = 999.0;

/// A fenced code slab.
const kCodeRadius = 6.0;

/// A code span.
const kInlineCodeRadius = 4.0;

/// A highlighter wash.
const kMarkRadius = 2.0;

// Section 6.9, durations.

/// Every tappable object's press and release.
const kPress = Duration(milliseconds: 90);

/// Arms the corner peel.
const kPeelLongPress = Duration(milliseconds: 140);

/// How long the finger must be still for a dog ear to catch.
const kDogEarCatchHold = Duration(milliseconds: 200);

/// A card or sheet lifting.
const kLift = Duration(milliseconds: 180);

/// The surround dimming behind a lift.
const kDim = Duration(milliseconds: 220);

/// The shelf chip underline travelling.
const kChipUnderline = Duration(milliseconds: 220);

/// A search button growing into a field.
const kSearchOpen = Duration(milliseconds: 220);
const kSearchClose = Duration(milliseconds: 160);

/// A card growing into the reading sheet.
const kOpenDocument = Duration(milliseconds: 320);
const kCloseDocument = Duration(milliseconds: 300);

/// The fold sweeping to the opposite corner, on the pageSettle spring.
const kFlipCommit = Duration(milliseconds: 380);

/// Chrome leaving on a scroll.
const kChromeOut = Duration(milliseconds: 180);
const kChromeIn = Duration(milliseconds: 180);

/// One highlighter stroke.
const kSweepPerWord = Duration(milliseconds: 140);

/// Between consecutive matches.
const kSweepStagger = Duration(milliseconds: 24);

/// Total sweep. The stagger compresses past 17 matches so it still fits.
const kSweepCap = Duration(milliseconds: 400);

/// An ordinary match becoming the current one.
const kSweepLive = Duration(milliseconds: 120);

/// One digit changing.
const kDigitRoll = Duration(milliseconds: 120);

/// Between digits, left to right.
const kDigitStagger = Duration(milliseconds: 20);

/// The match ticks appearing on the fore edge.
const kRailFade = Duration(milliseconds: 200);

/// The cell bar rising, on the valueBarSpring.
const kCellBarIn = Duration(milliseconds: 180);
const kCellBarOut = Duration(milliseconds: 140);

/// A spine opening and the open column collapsing.
const kColumnOpen = Duration(milliseconds: 240);

/// Switching workbook sheets.
const kSheetTabCross = Duration(milliseconds: 180);

/// A card coming apart. House value, unchanged.
const kDissolve = Duration(milliseconds: 3000);

/// A card gathering back. House value, unchanged.
const kMaterialize = Duration(milliseconds: 1200);

/// A signature setting into a page.
const kAbsorb = Duration(milliseconds: 900);

/// How long the undo pill lives, on a linear controller so a golden at any t
/// is reproducible.
const kUndoPill = Duration(milliseconds: 4000);

/// A signature stroke drying.
const kInkDry = Duration(milliseconds: 900);

/// Real content replacing a page's shimmer.
const kPageFadeIn = Duration(milliseconds: 160);

/// One shimmer sweep. House value.
const kShimmerPeriod = Duration(milliseconds: 640);

/// The riffle covering the reader.
const kRiffleIn = Duration(milliseconds: 220);
const kRiffleOut = Duration(milliseconds: 180);

/// A thumbnail growing into the sheet.
const kRiffleCommit = Duration(milliseconds: 300);

/// A fold settling to its rest inset.
const kFoldRest = Duration(milliseconds: 260);

/// The placement outline leaving.
const kStampOutlineFade = Duration(milliseconds: 160);

/// The chrome coming off a mark that has landed: the placement dim clearing
/// and the dashed outline leaving, both read off this one span.
const kStampSettle = Duration(milliseconds: 220);

/// The baseline guide holding, then fading.
const kSnapGuideHold = Duration(milliseconds: 220);
const kSnapGuideFade = Duration(milliseconds: 180);

/// A damaged, locked or scan card fading in.
const kStateCardIn = Duration(milliseconds: 240);

/// House dock values, unchanged.
const kDockEnter = Duration(milliseconds: 260);
const kDockExit = Duration(milliseconds: 140);
const kDockEnterStagger = Duration(milliseconds: 50);
const kDockHover = Duration(milliseconds: 180);

/// Where the centre of dock button [index] sits, in the lifted sheet's own
/// coordinates.
double dockButtonCenterX(int index, double containerWidth, int actionCount) {
  final middle = (actionCount - 1) / 2;
  return containerWidth / 2 + (index - middle) * kDockButtonSpacing;
}

/// Where the row of dock buttons sits below a lifted sheet of [sheetHeight].
double dockRowCenterY(double sheetHeight) =>
    sheetHeight + kDockGap + kDockButtonSize / 2;

// The shell: a top bar, a tab strip, a sort row and the body, with a drawer
// that slides over all four.

/// The top bar, holding the hamburger, the search pill and the avatar.
const kTopBarHeight = 56.0;
const kTopBarPaddingX = 12.0;

/// The hamburger's tap target. The glyph inside it is three lines
/// [kBurgerLine] wide and [kBurgerThickness] thick, [kBurgerGap] apart.
const kBurgerTarget = 40.0;
const kBurgerLine = 18.0;
const kBurgerThickness = 2.0;
const kBurgerGap = 5.0;

/// What the top and bottom lines shorten to once they have rotated into the
/// arrow, and how far the whole glyph walks left while they do.
const kBurgerLineShort = 9.0;
const kBurgerShift = 4.0;
const kBurgerAngle = 45.0;

/// The search pill, which takes whatever width the bar has left.
const kSearchPillHeight = 44.0;
const kSearchPillRadius = 22.0;

/// The folder target at the pill's right edge.
const kSearchFolderTarget = 36.0;
const kAvatarSize = 34.0;

/// The drawer takes this much of the screen, and stops at [kDrawerWidthMax] so
/// it stays a drawer on a wide phone instead of becoming a second screen.
const kDrawerWidthFraction = 0.84;
const kDrawerWidthMax = 320.0;

/// How wide the drawer is on a screen of [screenWidth].
double drawerWidth(double screenWidth) =>
    (screenWidth * kDrawerWidthFraction).clamp(0, kDrawerWidthMax);

const kDrawerRowHeight = 52.0;
const kDrawerRowRadius = 26.0;
const kDrawerRowPaddingX = 16.0;
const kDrawerRowGlyph = 24.0;

/// Between a drawer row's glyph and its label.
const kDrawerRowGap = 24.0;

/// How far the divider before the last group is inset at both ends.
const kDrawerDividerInset = 16.0;

/// The tab strip, scrolling horizontally under the bar.
const kTabStripHeight = 44.0;
const kTabStripPaddingX = 12.0;
const kTabGap = 8.0;
const kTabPillHeight = 32.0;
const kTabPillRadius = 16.0;
const kTabPillPaddingX = 14.0;

/// Between a tab's label and its count.
const kTabCountGap = 6.0;

/// The sort row, holding the current sort on the left and the view toggles on
/// the right.
const kSortRowHeight = 48.0;
const kSortRowPaddingX = 12.0;

/// The circle round the sort direction arrow, which turns over when the
/// direction flips.
const kSortArrowCircle = 24.0;
const kSortArrowFlip = Duration(milliseconds: 200);

/// One of the two view toggles, list then grid.
const kViewToggleWidth = 40.0;
const kViewToggleHeight = 32.0;
const kViewToggleRadius = 16.0;
const kViewToggleGap = 8.0;

/// The sort menu, anchored under the sort label.
const kSortMenuWidth = 240.0;
const kSortMenuRadius = 12.0;
const kSortMenuOffset = 8.0;
const kSortMenuRowHeight = 48.0;
const kSortMenuPaddingLeft = 16.0;
const kSortMenuPaddingRight = 20.0;

/// The gutter a check sits in, left aligned, so the labels of checked and
/// unchecked rows start at the same x.
const kSortMenuGutter = 40.0;
const kSortMenuCheck = 18.0;
const kSortMenuIn = Duration(milliseconds: 160);

/// The menu grows from this about its top left corner.
const kSortMenuScaleFrom = 0.94;

// The list body: one row per document.
const kListRowHeight = 72.0;
const kListRowPaddingX = 12.0;

/// The rule under a row starts here, under the title rather than under the
/// mark, so the marks read as a column and the rules as a list.
const kListRuleInset = 64.0;

/// Between the mark and the title column.
const kListMarkGap = 14.0;

/// Between the title and the meta line under it.
const kListTitleGap = 4.0;

/// The overflow target, holding three dots [kOverflowDot] across with
/// [kOverflowDotGap] between them.
const kOverflowTarget = 40.0;
const kOverflowDot = 4.0;
const kOverflowDotGap = 3.0;

/// The overflow menu, hung off the three dots that opened it.
///
/// It borrows the sort menu's width, radius, row height and arrival, because
/// the two are the same object asking about different things and a second set
/// of numbers would make them look like two designs. What is its own is the
/// gutter, which holds a glyph rather than a check, and the corner it grows
/// from, which is the one nearest its own three dots.
const kOverflowMenuGutter = 32.0;
const kOverflowMenuGlyph = 17.0;
const kOverflowMenuOffset = 4.0;

/// A row's reading progress, inset to the title's left edge.
const kListProgressWidth = 140.0;
const kListProgressHeight = 2.0;

// The grid body: two columns of cards, each showing its document's real first
// page.
const kGridColumns = 2;
const kGridGap = 12.0;
const kGridPadding = 12.0;
const kGridCardRadius = 12.0;

/// The card's header, above the thumbnail.
const kGridCardHeaderHeight = 44.0;
const kGridCardPadding = 10.0;

/// Between the mark and the title in a card header.
const kGridHeaderGap = 8.0;
const kGridOverflowTarget = 32.0;

/// The thumbnail is the card's full width, and this much taller than it is
/// wide, which is a page's proportion without being a page's exact one.
const kThumbnailAspect = 1 / 1.15;

/// Every rule in the app is one physical pixel. Divided by the view's device
/// pixel ratio for logical units, which is what `hairline` does.
const kHairline = 1.0;
