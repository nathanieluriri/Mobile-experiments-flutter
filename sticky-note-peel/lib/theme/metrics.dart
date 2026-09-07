/// Layout, fold, dock and animation numbers, kept together so a change lands in
/// one place.
library;

// Screen layout.
const kScreenHorizontalPadding = 20.0;
const kHeaderHorizontalPadding = 17.5;
const kHeaderVerticalPadding = 7.0;
const kHeaderButtonSize = 38.5;
const kHeaderButtonRadius = 14.0;
const kLargeTitleTopMargin = 7.0;

// Inside a note.
const kNoteRadius = 14.0;
const kNotePadding = 14.0;
const kNoteTitleRightPadding = 28.0;
const kNoteTitleBottomMargin = 7.0;
const kChipRowTopMargin = 10.5;
const kChipGap = 7.0;
const kChipHorizontalPadding = 10.5;
const kChipVerticalPadding = 5.0;
const kChipIconGap = 3.5;
const kChecklistRowGap = 9.0;
const kChecklistLabelGap = 10.0;
const kChecklistBoxSize = 17.0;
const kChecklistBoxStroke = 1.5;
const kMetaTopMargin = 10.0;
const kNoteListGap = 16.0;
const kNoteListBottomPadding = 130.0;
const kComposeButtonBottomMargin = 22.0;
const kInitialNoteHeight = 180.0;
const kNotesScreenTitle = 'All notes';

/// Scroll ranges that collapse the large title into the header.
const kSmallTitleRange = (22.0, 58.0);
const kLargeTitleRange = (0.0, 44.0);
const kOverscrollRange = (-80.0, 0.0);
const kOverscrollScale = 1.08;
const kTitleShift = 8.0;

// The fold.
const kFoldRestInset = 26.0;
const kFoldEdgeMargin = 4.0;
const kFoldHandleSize = 72.0;
const kNoteFlapShade = -0.2;
const kPeelLongPress = Duration(milliseconds: 140);

// The drawer of lists.
const kDrawerWidthFraction = 0.78;
const kDrawerMaxWidth = 300.0;
const kDrawerPadding = 18.0;
const kDrawerSectionGap = 22.0;
const kDrawerRowGap = 10.0;
const kDrawerRowHeight = 46.0;
const kDrawerRowRadius = 10.0;
const kDrawerFoldInset = 13.0;
const kDrawerScrimOpacity = 0.66;
const kDrawerFlingVelocity = 400.0;

// Writing a new note.
const kSwatchSize = 34.0;
const kSwatchFoldInset = 9.0;
const kComposeMargin = 24.0;
const kComposeActionSize = 32.0;
const kComposeActionGap = 8.0;

// The dock.
const kDockGap = 18.0;
const kDockButtonSize = 54.0;
const kDockButtonSpacing = 78.0;
const kDockHoverRadius = kDockButtonSize * 0.85;
const kDockHoverScale = 1.18;
const kDockTriggerScaleBoost = 0.06;
const kDockRecedeScale = 0.85;

// Dimming and lift.
const kChromeDimAmount = 0.78;
const kDimmedNoteOpacity = 0.25;
const kLiftScaleDelta = 0.02;
const kRemovalShrink = 0.9;
const kLiftShadowOpacity = 0.35;

// Durations.
const kDimDuration = Duration(milliseconds: 220);
const kLiftDuration = Duration(milliseconds: 180);
const kSettleDuration = Duration(milliseconds: 200);
const kRemovalTravelDuration = Duration(milliseconds: 170);
const kRemovalShrinkDuration = Duration(milliseconds: 280);
const kRemovalShrinkDelay = Duration(milliseconds: 80);
const kNoteShimmerDuration = Duration(milliseconds: 640);
const kDockHoverDuration = Duration(milliseconds: 180);
const kDockRecedeDuration = Duration(milliseconds: 180);
const kDockShimmerDuration = Duration(milliseconds: 520);
const kDockEnterDuration = Duration(milliseconds: 260);
const kDockExitDuration = Duration(milliseconds: 140);
const kDockEnterStagger = Duration(milliseconds: 50);

/// How far a dock button rises into place as it fades in.
const kDockEnterRise = 25.0;

// Shimmer bands.
const kNoteShimmerHeight = 300.0;
const kNoteShimmerBand = 96.0;
const kNoteShimmerOpacity = 0.28;
const kNoteShimmerSkew = 14.0;
const kDockShimmerBand = 30.0;
const kDockShimmerOpacity = 0.55;
const kDockShimmerSkew = 16.0;

/// Where [value] sits between the two ends of [range], clamped to 0 to 1.
double rangeProgress(double value, (double, double) range) {
  final (start, end) = range;
  return ((value - start) / (end - start)).clamp(0, 1);
}

/// Where the centre of dock button [index] sits, in note coordinates.
double dockButtonCenterX(int index, double containerWidth, int actionCount) {
  final middle = (actionCount - 1) / 2;
  return containerWidth / 2 + (index - middle) * kDockButtonSpacing;
}

/// Where the row of dock buttons sits below a note of [noteHeight].
double dockRowCenterY(double noteHeight) =>
    noteHeight + kDockGap + kDockButtonSize / 2;
