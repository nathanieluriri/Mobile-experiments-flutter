import 'package:flutter/painting.dart';

import 'colors.dart';

/// Family every label in the app is set in.
const appFontFamily = 'Inter';

/// The app's type scale. Each style carries its own family, colour and blank
/// decoration so text reads the same wherever it is placed.
abstract final class AppText {
  /// Small tracked capitals above the deck.
  static const eyebrow = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: AppColors.tertiaryLabel,
  );

  /// Focused album title.
  static const nowPlayingTitle = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.label,
  );

  /// Focused album artist.
  static const nowPlayingArtist = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 16,
    color: AppColors.secondaryLabel,
  );

  /// Elapsed and total time, in figures of even width so nothing shifts.
  static const time = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 12,
    color: AppColors.tertiaryLabel,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Screen heading on the list tabs.
  static const heading = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.label,
  );

  /// Album title under a grid tile.
  static const tileTitle = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.label,
  );

  /// Album artist under a grid tile.
  static const tileArtist = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 13,
    color: AppColors.secondaryLabel,
  );

  /// Playlist name in a library row.
  static const rowTitle = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.label,
  );

  /// Track count in a library row.
  static const rowSubtitle = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 13,
    color: AppColors.secondaryLabel,
  );

  /// Dock label, tinted by whether its tab is selected.
  static const dockLabel = TextStyle(
    fontFamily: appFontFamily,
    decoration: TextDecoration.none,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
}
