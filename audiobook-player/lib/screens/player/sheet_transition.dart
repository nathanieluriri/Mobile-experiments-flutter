import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show EdgeInsets;

import '../../theme/layout.dart';
import '../../theme/motion.dart';

/// Every value the player sheet animates, read off one progress number.
///
/// 0 is the mini player sitting above the tab bar, 1 is the full sheet. The
/// blur is the one figure that could not be carried over as written: the
/// original asks its blur view for intensity 0 to 55, which is not a Gaussian
/// radius, so the radius here is the one measured off the original running on
/// the phone.
class SheetTransition {
  const SheetTransition({
    required this.progress,
    required this.window,
    required this.insets,
  });

  final double progress;
  final Size window;
  final EdgeInsets insets;

  static const _blurSigmaAtFullOpen = 10.0;
  static const _tintAtFullOpen = 0.42;
  static const _scrimAtFullOpen = 0.35;

  double get tabBarSpace => Layout.tabBarHeight + insets.bottom;
  double get expandedArtworkSize => window.width - 88;
  double get expandedArtworkTop => insets.top + 68;
  double get dragRange => window.height - Layout.miniPlayerHeight - tabBarSpace;

  double get bottom =>
      interpolate(progress, [0, 0.4], [tabBarSpace, 0], clamp: true);
  double get height =>
      interpolate(progress, [0, 1], [Layout.miniPlayerHeight, window.height]);
  double get topRadius =>
      interpolate(progress, [0, 0.9, 1], [20, 28, 0]).clamp(0.0, 28.0);

  double get blurSigma =>
      interpolate(progress, [0, 1], [0, _blurSigmaAtFullOpen], clamp: true);
  double get tintOpacity =>
      interpolate(progress, [0, 1], [0, _tintAtFullOpen], clamp: true);
  double get scrimOpacity =>
      interpolate(progress, [0, 1], [0, _scrimAtFullOpen], clamp: true);

  double get artworkSize =>
      interpolate(progress, [0, 1], [44, expandedArtworkSize]);
  double get artworkTop =>
      interpolate(progress, [0, 1], [16, expandedArtworkTop]);
  double get artworkLeft => interpolate(
    progress,
    [0, 1],
    [20, (window.width - expandedArtworkSize) / 2],
  );
  double get artworkRadius =>
      interpolate(progress, [0, 1], [10, 24]).clamp(0.0, 24.0);

  double get handleTop => interpolate(progress, [0, 1], [8, insets.top + 10]);

  double get miniOpacity =>
      interpolate(progress, [0, 0.12], [1, 0], clamp: true);
  bool get miniTakesTaps => progress < 0.05;

  double get expandedOpacity =>
      interpolate(progress, [0.45, 0.9], [0, 1], clamp: true);
  double get expandedTranslateY =>
      interpolate(progress, [0.45, 1], [32, 0], clamp: true);
  bool get expandedTakesTaps => progress > 0.95;

  /// How tall the expanded view's artwork gap has to be.
  double get artworkSpacerHeight => expandedArtworkTop + expandedArtworkSize;
}
